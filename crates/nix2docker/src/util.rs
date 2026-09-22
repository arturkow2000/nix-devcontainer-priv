use std::{
    pin::Pin,
    task::{Context, Poll, ready},
};

use const_format::concatcp;
use containerd_client::{
    services::v1::{StreamInit, streaming_client::StreamingClient},
    types::transfer::Data,
};
use futures_util::{Sink, SinkExt as _, StreamExt};
use prost::{Message, Name};
use prost_types::Any;
use tokio::{
    io::{self, AsyncRead},
    sync::{mpsc, watch},
};
use tokio_stream::wrappers::{ReceiverStream, WatchStream};
use tokio_util::{io::ReaderStream, sync::PollSender};
use tonic::{Extensions, Request, Streaming, metadata::MetadataMap};

const CHUNK_SIZE: usize = 4096;

#[derive(Debug, Snafu)]
pub enum UploadError {
    #[snafu(display("I/O error reading from source"))]
    Io { source: io::Error },

    #[snafu(transparent)]
    Grpc { source: GrpcError },
}

#[derive(Debug, Snafu)]
#[snafu(display("gRPC call {request} failed ({status})"))]
pub struct GrpcError {
    pub request: &'static str,
    pub status: tonic::Status,
}

/// Bidirectional stream for transmitting data using ContainerD streaming service.
#[derive(Debug)]
pub struct ContainerdStreamingChannel {
    init_notify: watch::Receiver<bool>,
    stream: Streaming<Any>,
    init_tx: watch::Sender<bool>,
    stream_tx: PollSender<Any>,
}
impl ContainerdStreamingChannel {
    pub async fn new(
        streaming: &mut StreamingClient<tonic::transport::Channel>,
        id: String,
        meta: MetadataMap,
    ) -> Result<Self, GrpcError> {
        let (init_tx, init_notify) = watch::channel(false);
        let (stream_tx, rx) = mpsc::channel(1);
        // Do it now so unwrap never fails.
        stream_tx
            .send(Any {
                type_url: StreamInit::full_name(),
                value: StreamInit { id: id.clone() }.encode_to_vec(),
            })
            .await
            .unwrap();
        let stream = streaming
            .stream(Request::from_parts(
                meta,
                Extensions::new(),
                ReceiverStream::new(rx),
            ))
            .await
            .map_err(|status| GrpcError {
                request: concatcp!(StreamInit::PACKAGE, ".", StreamInit::NAME),
                status,
            })?
            .into_inner();
        Ok(Self {
            init_notify,
            stream,
            init_tx,
            stream_tx: PollSender::new(stream_tx),
        })
    }

    /// Wait for channel initialization to complete.
    ///
    /// If stream is dropped before stream has been initialized the future will never complete.
    pub fn wait_init<'f>(&self) -> impl Future<Output = Result<(), GrpcError>> + 'f {
        let mut rx = self.init_notify.clone();
        async move {
            loop {
                let v = *rx.borrow_and_update();
                if v {
                    return Ok(());
                }
                if rx.changed().await.is_err() {
                    warn!("stream dropped before initialization complete");
                    return Err(GrpcError {
                        request: concatcp!(StreamInit::PACKAGE, ".", StreamInit::NAME),
                        status: tonic::Status::cancelled("stream cancelled"),
                    });
                }
            }
        }
    }

    pub fn new_sink(&self) -> ContainerdSink {
        ContainerdSink {
            tx: self.stream_tx.clone(),
            init: Some(WatchStream::from_changes(self.init_notify.clone())),
            init_cache: false,
        }
    }

    /// Drive the stream to completion
    pub async fn process(mut self) -> Result<(), GrpcError> {
        let mut init_done = false;
        // Stream dies when all producers go away.
        drop(self.stream_tx);
        loop {
            match self.stream.message().await {
                Ok(Some(resp)) => {
                    if resp.type_url == "google.protobuf.Empty" && !init_done {
                        self.init_tx.send(true).unwrap();
                        init_done = true;
                    }
                }
                Ok(None) => {
                    if !init_done {
                        return Err(GrpcError {
                            request: concatcp!(StreamInit::PACKAGE, ".", StreamInit::NAME),
                            status: tonic::Status::cancelled("stream closed"),
                        });
                    }
                    break;
                }
                Err(status) => {
                    return Err(GrpcError {
                        request: concatcp!(Data::PACKAGE, ".", Data::NAME),
                        status,
                    });
                }
            }
        }
        Ok(())
    }
}

#[derive(Debug)]
pub struct ContainerdSink {
    tx: PollSender<Any>,
    init: Option<WatchStream<bool>>,
    init_cache: bool,
}
impl ContainerdSink {
    fn _poll_ready(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Result<(), tonic::Status>> {
        // cache init status to avoid synchronization on each call
        if !self.init_cache {
            while let Some(v) = ready!(self.init.as_mut().unwrap().poll_next_unpin(cx)) {
                if v {
                    debug!("stream ready");
                    self.init_cache = true;
                    break;
                }
            }
        }

        if !self.init_cache {
            return Poll::Ready(Err(tonic::Status::cancelled("stream closed")));
        }

        Poll::Ready(Ok(()))
    }
}
impl Sink<Any> for ContainerdSink {
    type Error = tonic::Status;

    fn poll_ready(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        ready!(self.as_mut()._poll_ready(cx))?;

        self.tx
            .poll_ready_unpin(cx)
            .map_err(|_| tonic::Status::cancelled("stream closed"))
    }

    fn start_send(mut self: Pin<&mut Self>, item: Any) -> Result<(), Self::Error> {
        self.tx
            .start_send_unpin(item)
            .map_err(|_| tonic::Status::cancelled("stream closed"))
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        ready!(self.as_mut()._poll_ready(cx))?;

        self.tx
            .poll_flush_unpin(cx)
            .map_err(|_| tonic::Status::cancelled("stream closed"))
    }

    fn poll_close(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        ready!(self.as_mut()._poll_ready(cx))?;

        self.tx
            .poll_close_unpin(cx)
            .map_err(|_| tonic::Status::cancelled("stream closed"))
    }
}

pub async fn copy_to_containerd<R: AsyncRead>(
    r: Pin<&mut R>,
    sink: &mut ContainerdSink,
) -> Result<(), UploadError> {
    let mut chunk = 0;
    let mut r = ReaderStream::with_capacity(r, CHUNK_SIZE);
    while let Some(result) = r.next().await {
        match result {
            Ok(data) => {
                trace!(chunk, "uploading");
                sink.feed(Any {
                    type_url: Data::type_url(),
                    value: Data {
                        data: data.to_vec(),
                    }
                    .encode_to_vec(),
                })
                .await
                .map_err(|status| UploadError::Grpc {
                    source: GrpcError {
                        request: concatcp!(Data::PACKAGE, ".", Data::NAME),
                        status,
                    },
                })?;
                trace!(chunk, "done");
                chunk += 1;
            }
            Err(source) => return Err(UploadError::Io { source }),
        }
    }

    Ok(())
}

pub fn goos() -> &'static str {
    cfg_select! {
        target_os = "linux" => "linux",
    }
}

pub fn goarch() -> &'static str {
    cfg_select! {
        target_arch = "x86_64" => "amd64",
        target_arch = "x86" => "386",
        target_arch = "arm" => "arm",
        target_arch = "aarch64" => "arm64",
    }
}
