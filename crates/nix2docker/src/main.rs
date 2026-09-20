#[macro_use]
extern crate tracing;

#[macro_use]
extern crate snafu;

mod util;

use std::{
    cmp::min,
    collections::{BTreeMap, HashMap},
    fmt::Debug,
    io::{SeekFrom, stderr},
    path::PathBuf,
    pin::Pin,
};

use async_tar::{Archive, EntryType};
use clap::Parser;
use containerd_client::{
    services::v1::{CreateRequest, DeleteRequest, StreamInit, TransferRequest},
    types::{
        Platform,
        transfer::{Data, ImageImportStream, ImageReference, ImageStore, UnpackConfiguration},
    },
    with_namespace,
};
use futures_util::StreamExt;
use oci_spec::image::{ImageConfiguration, ImageIndex, ImageManifest, MediaType, OciLayout};
use prost::{Message, Name};
use prost_types::Any;
use serde::de::DeserializeOwned;
use snafu::{IntoError as _, ResultExt};
use tokio::{
    fs::File,
    io::{self, AsyncRead, AsyncReadExt as _, AsyncSeek, AsyncSeekExt as _, ReadBuf},
    join,
    sync::{mpsc, oneshot},
};
use tokio_stream::wrappers::ReceiverStream;
use tonic::Request;
use tracing::field;
use tracing_subscriber::EnvFilter;
use uuid::Uuid;

use crate::util::{ContainerdStreamingChannel, GrpcError, UploadError, copy_to_containerd};

const DOCKER_NS: &str = "moby";

#[derive(Parser)]
struct Options {
    file: PathBuf,

    /// containerd address
    #[arg(long, default_value = "/run/containerd/containerd.sock")]
    address: PathBuf,

    /// Set platform (e.g. linux/amd64, linux/arm64)
    #[arg(long, value_parser = parse_platform, default_value_t = default_platform())]
    platform: String,
}

fn parse_platform(s: &str) -> Result<String, String> {
    let invalid_value = || format!("invalid platform {s}");
    let invalid_chars = |c: char| !c.is_alphanumeric();
    let (os, arch) = s.split_once("/").ok_or_else(invalid_value)?;
    if os.find(invalid_chars).is_some() || arch.find(invalid_chars).is_some() {
        return Err(invalid_value());
    }
    Ok(s.to_string())
}

fn default_platform() -> String {
    format!("{}/{}", util::goos(), util::goarch())
}

#[derive(Debug, Snafu)]
enum Error {
    #[snafu(display("can't connect to containerd {}", path.display()))]
    ContainerdConnectError {
        path: PathBuf,
        source: tonic::transport::Error,
    },

    #[snafu(display("can't open archive \"{}\"", path.display()))]
    ArchiveOpenError { path: PathBuf, source: io::Error },

    #[snafu(display("error while parsing archive"))]
    ArchiveParseError { source: io::Error },

    #[snafu(display("can't read \"{path}\" (from archive)"))]
    ArchiveFileReadError { path: String, source: io::Error },

    #[snafu(display("failed to deserialize \"{path}\" (from archive)"))]
    ArchiveFileDeserializeError {
        path: String,
        source: serde_json::Error,
    },

    #[snafu(display("unsupported OCI layout version \"{version}\""))]
    UnsupportedOciLayoutVersion { version: String },

    #[snafu(display("unsupported OCI index schema version {version}"))]
    UnsupportedOciIndexSchemaVersion { version: u32 },

    #[snafu(display("failed to create lease"))]
    LeaseCreateError { source: GrpcError },

    #[snafu(display("no manifest for platform {platform}"))]
    NoManifest { platform: String },

    #[snafu(display("blob id {id} missing"))]
    MissingBlob { id: String },

    #[snafu(display("failed to upload {id}"))]
    UploadError { id: String, source: UploadError },
}

#[tokio::main]
async fn main() -> eyre::Result<()> {
    let opts = Options::parse();
    tracing_subscriber::fmt()
        .with_writer(stderr)
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    run(opts).await?;
    Ok(())
}

async fn run(opts: Options) -> Result<(), Error> {
    let containerd = containerd_client::Client::from_path(&opts.address)
        .await
        .with_context(|_| ContainerdConnectSnafu {
            path: &opts.address,
        })?;
    let mut tar = File::open(&opts.file)
        .await
        .with_context(|_| ArchiveOpenSnafu {
            path: opts.file.clone(),
        })?;
    let mut tar_raw = tar.try_clone().await.unwrap();
    let tar = async_tar::Archive::new(&mut tar);

    let mut leases = containerd.leases();
    let lease = {
        let mut labels = HashMap::new();
        //labels.insert(
        //    "containerd.io/gc.bref.image".to_string(),
        //    image_name.to_string(),
        //);
        labels.insert(
            "containerd.io/gc.expire".to_string(),
            chrono::Utc::now().to_rfc3339(),
        );
        let lease_id = format!("{}", Uuid::new_v4());
        let resp = leases
            .create(with_namespace!(
                CreateRequest {
                    id: lease_id,
                    labels,
                },
                DOCKER_NS
            ))
            .await
            .map_err(|status| GrpcError {
                request: CreateRequest::NAME,
                status,
            })
            .context(LeaseCreateSnafu)?;
        resp.into_inner().lease.unwrap()
    };

    let result = upload_tar(&containerd, tar, &mut tar_raw, &opts.platform, &lease.id).await;

    if let Err(status) = leases
        .delete(with_namespace!(
            DeleteRequest {
                id: lease.id.clone(),
                sync: false,
            },
            DOCKER_NS
        ))
        .await
    {
        warn!(
            status = field::display(status),
            id = lease.id,
            "failed to delete lease"
        );
    }

    result
}

async fn upload_tar<R: AsyncRead + AsyncSeek + Unpin>(
    containerd: &containerd_client::Client,
    tar: Archive<&mut R>,
    tar_raw: &mut File,
    platform: &str,
    lease: &str,
) -> Result<(), Error> {
    struct FileMeta {
        offset: u64,
        size: u64,
    }

    let mut files = HashMap::new();
    let mut entries = tar.entries().context(ArchiveParseSnafu)?;
    while let Some(r) = entries.next().await {
        let entry = r.context(ArchiveParseSnafu)?;
        let path = match String::from_utf8(entry.path_bytes().to_vec()) {
            Ok(path) => path,
            Err(_) => {
                warn!("ignoring entry with invalid UTF-8");
                continue;
            }
        };
        if entry.header().entry_type() != EntryType::Regular {
            continue;
        }
        files.insert(
            path,
            FileMeta {
                offset: entry.raw_file_position(),
                size: entry.header().size().unwrap(),
            },
        );
    }

    async fn json_deserialize_from_file<T: DeserializeOwned, R: AsyncRead + AsyncSeek + Unpin>(
        archive: &mut R,
        files: &HashMap<String, FileMeta>,
        path: &str,
    ) -> Result<T, Error> {
        let entry = files.get(path).ok_or_else(|| {
            ArchiveFileReadSnafu { path }.into_error(io::ErrorKind::NotFound.into())
        })?;
        archive
            .seek(SeekFrom::Start(entry.offset))
            .await
            .with_context(|_| ArchiveFileReadSnafu { path })?;
        let mut data = vec![];
        archive
            .take(entry.size)
            .read_to_end(&mut data)
            .await
            .with_context(|_| ArchiveFileReadSnafu { path })?;
        serde_json::from_slice(&data[..]).with_context(|_| ArchiveFileDeserializeSnafu { path })
    }

    let layout: OciLayout = json_deserialize_from_file(tar_raw, &files, "oci-layout").await?;
    ensure!(
        layout.image_layout_version().starts_with("1."),
        UnsupportedOciLayoutVersionSnafu {
            version: layout.image_layout_version()
        }
    );

    // Not required by OCI spec
    let index: ImageIndex = json_deserialize_from_file(tar_raw, &files, "index.json").await?;
    ensure!(
        index.schema_version() == 2,
        UnsupportedOciIndexSchemaVersionSnafu {
            version: index.schema_version()
        }
    );
    for desc in index.manifests() {
        if *desc.media_type() != MediaType::ImageManifest {
            continue;
        }
        let digest = desc.digest();
        let manifest_path = format!("blobs/{}/{}", digest.algorithm(), digest.digest());

        let manifest: ImageManifest =
            match json_deserialize_from_file(tar_raw, &files, &manifest_path).await {
                Ok(manifest) => manifest,
                Err(error) => {
                    warn!(
                        error = field::display(error),
                        manifest_path, "can't read manifest, ignoring"
                    );
                    continue;
                }
            };
        if manifest.schema_version() != 2 {
            warn!(
                manifest_path,
                schema_version = manifest.schema_version(),
                "unsupported manifest schema version, ignoring"
            );
            continue;
        }
        let config_desc = manifest.config();
        if *config_desc.media_type() != MediaType::ImageConfig {
            warn!(
                "media-type" = field::display(config_desc.media_type()),
                "unsupported media-type for config descriptor, ignoring"
            );
            continue;
        }
        let config_path = format!(
            "blobs/{}/{}",
            config_desc.digest().algorithm(),
            config_desc.digest().digest()
        );
        let config: ImageConfiguration =
            match json_deserialize_from_file(tar_raw, &files, &config_path).await {
                Ok(config) => config,
                Err(error) => {
                    warn!(error = field::display(error), "can't read config, ignoring");
                    continue;
                }
            };
        let manifest_platform = format!("{}/{}", config.os(), config.architecture());
        if manifest_platform != platform {
            debug!("ignoring manifest with platform {manifest_platform}");
            continue;
        }
        info!("{platform} config: {config:?}");

        for layer in manifest.layers() {
            let layer_path = format!(
                "blobs/{}/{}",
                layer.digest().algorithm(),
                layer.digest().digest()
            );
            let meta = files.get(&layer_path).unwrap();

            tar_raw
                .seek(SeekFrom::Start(meta.offset))
                .await
                .map_err(|source| Error::UploadError {
                    id: layer.digest().to_string(),
                    source: UploadError::Io { source },
                })?;
            upload_layer(
                &containerd,
                Pin::new(&mut tar_raw.take(meta.size)),
                platform,
                lease,
            )
            .await
            .with_context(|_| UploadSnafu {
                id: layer.digest().to_string(),
            })?;
        }
    }

    Ok(())
}

async fn upload_layer<R: AsyncRead>(
    containerd: &containerd_client::Client,
    layer: Pin<&mut R>,
    platform: &str,
    lease: &str,
) -> Result<(), UploadError> {
    let mut streaming = containerd.streaming();
    let stream_id = Uuid::new_v4();

    let mut ch = ContainerdStreamingChannel::new(&mut streaming, stream_id.to_string(), {
        let mut meta = BTreeMap::new();
        meta.insert("containerd-namespace", DOCKER_NS.to_string());
        meta.insert("containerd-lease", lease.to_string());
        meta
    })
    .await
    .unwrap();
    let stream_wait = ch.wait_init();
    let mut sink = ch.new_sink();
    let copy_task = copy_to_containerd(layer, &mut sink);

    let transfer_task = async move {
        error!("wait!");
        stream_wait.await?;

        Result::<_, tonic::Status>::Ok(())
    };

    info!("waiting for stream");
    let (x, y, z) = join!(ch.process(), transfer_task, copy_task);

    info!("FDFDF");

    Ok(())

    //let (stream_init_tx, stream_init_done) = oneshot::channel();
    //let mut stream_init_tx = Some(stream_init_tx);
    //let (tx, rx) = mpsc::channel(1);
    //tx.send(Any {
    //    type_url: StreamInit::full_name(),
    //    value: StreamInit {
    //        id: stream_id.to_string(),
    //    }
    //    .encode_to_vec(),
    //})
    //.await
    //.unwrap();
}

/*async fn upload_to_stream<R: AsyncRead>(
    mut from: Pin<&mut R>,
    to: &mut mpsc::Sender<Any>,
    max_chunk_size: usize,
) -> Result<(), UploadError> {
    let mut chunk = 0;

    info!("uploading file");
    let mut eof = false;
    while !eof {
        debug!(i = chunk, "chunk");
        let mut buf = Vec::with_capacity(max_chunk_size);
        let mut rb = ReadBuf::uninit(buf.spare_capacity_mut());
        let mut filled_old = rb.filled().len();

        while rb.remaining() > 0 {
            from.as_mut().read_buf(&mut rb).await?;
            if filled_old == rb.filled().len() {
                eof = true;
            }
            filled_old = rb.filled().len();
            if eof {
                break;
            }
        }
        if filled_old == 0 {
            break;
        }

        // Safety: data has been initialized
        unsafe { buf.set_len(filled_old) };
        if to
            .send(Any {
                type_url: Data::type_url(),
                value: Data { data: buf }.encode_to_vec(),
            })
            .await
            .is_err()
        {
            return Err(UploadError::StreamClosed);
        }

        chunk += 1;
    }

    Ok(())
}*/

/*async fn upload_archive<R: AsyncRead + Unpin>(
    containerd: &containerd_client::Client,
    archive: &mut R,
    platform: &str,
) {
    const CHUNK_SIZE: usize = 64;
    let mut streaming = containerd.streaming();
    let stream_id = Uuid::new_v4();
    let (stream_init_tx, stream_init_done) = oneshot::channel();
    let mut stream_init_tx = Some(stream_init_tx);
    let (tx, rx) = mpsc::channel(1);
    tx.send(Any {
        type_url: StreamInit::full_name(),
        value: StreamInit {
            id: stream_id.to_string(),
        }
        .encode_to_vec(),
    })
    .await
    .unwrap();

    let file_upload_task = async move {
        let mut chunk = 0;

        info!("uploading file");
        let mut eof = false;
        while !eof {
            debug!(i = chunk, "chunk");
            let mut buf = Vec::with_capacity(CHUNK_SIZE);
            let mut rb = ReadBuf::uninit(buf.spare_capacity_mut());
            let mut filled_old = rb.filled().len();

            while rb.remaining() > 0 {
                archive.read_buf(&mut rb).await?;
                if filled_old == rb.filled().len() {
                    eof = true;
                }
                filled_old = rb.filled().len();
                if eof {
                    break;
                }
            }
            if filled_old == 0 {
                break;
            }

            // Safety: data has been initialized
            unsafe { buf.set_len(filled_old) };
            if tx
                .send(Any {
                    type_url: Data::type_url(),
                    value: Data { data: buf }.encode_to_vec(),
                })
                .await
                .is_err()
            {
                error!("channel closed");
                return Result::<_, io::Error>::Ok(());
            }

            chunk += 1;
        }

        Result::<_, io::Error>::Ok(())
    };
    let stream_task = async {
        let resp_stream = streaming
            .stream({
                let mut req = Request::new(ReceiverStream::new(rx));
                let md = req.metadata_mut();
                md.insert("containerd-namespace", DOCKER_NS.parse().unwrap());
                req
            })
            .await
            .unwrap();
        let mut resp_stream = resp_stream.into_inner();
        loop {
            match resp_stream.message().await {
                Ok(Some(resp)) => {
                    if resp.type_url == "google.protobuf.Empty"
                        && let Some(tx) = stream_init_tx.take()
                    {
                        // We need to wait for stream to initialize, during init a name is assigned
                        // to the stream, we need to wait before issuing TransferRequest.
                        debug!("stream initialized");
                        let _ = tx.send(());
                    }
                }
                Ok(None) => {
                    break;
                }
                Err(status) => {
                    error!("stream error: {status}");
                }
            }
        }
    };
    let transfer_task = async {
        stream_init_done.await.unwrap();
        let (os, arch) = platform.split_once("/").unwrap();
        let mut req = Request::new(TransferRequest {
            source: Some(Any {
                type_url: ImageImportStream::full_name(),
                value: ImageImportStream {
                    stream: stream_id.to_string(),
                    media_type: String::new(),
                    force_compress: false,
                }
                .encode_to_vec(),
            }),
            destination: Some(Any {
                type_url: ImageStore::full_name(),
                value: ImageStore {
                    name: String::new(),
                    labels: HashMap::new(),
                    platforms: vec![Platform {
                        os: os.to_string(),
                        architecture: arch.to_string(),
                        variant: String::new(),
                        os_version: String::new(),
                    }],
                    all_metadata: false,
                    manifest_limit: 0,
                    extra_references: vec![ImageReference {
                        name: "dd".to_string(),
                        is_prefix: false,
                        allow_overwrite: false,
                        add_digest: false,
                        skip_named_digest: false,
                    }],
                    unpacks: vec![UnpackConfiguration {
                        platform: Some(Platform {
                            os: os.to_string(),
                            architecture: arch.to_string(),
                            variant: String::new(),
                            os_version: String::new(),
                        }),
                        snapshotter: "nix".to_string(),
                    }],
                }
                .encode_to_vec(),
            }),
            options: None,
        });
        let md = req.metadata_mut();
        md.insert("containerd-namespace", DOCKER_NS.parse().unwrap());

        let resp = containerd.transfer().transfer(req).await.unwrap();
        info!("resp: {resp:?}")
        //let req = with_namespace!();
    };
    let (x, y, z) = join!(file_upload_task, stream_task, transfer_task);
    x.unwrap();

    //let import_src = ImageImportStream {stream:}
}*/

/*use async_tar::{Archive, EntryType};
use clap::Parser;
use containerd_client::{
    services::v1::{
        CreateRequest, DeleteRequest, WriteAction, WriteContentRequest,
        content_client::ContentClient,
    },
    with_namespace,
};
use futures_util::StreamExt;
use oci_spec::image::{
    Digest, ImageConfiguration, ImageIndex, ImageManifest, MediaType, OciLayout,
};
use prost::Name;
use serde::de::DeserializeOwned;
use snafu::{IntoError, ResultExt, Snafu};
use tokio::{
    fs::File,
    io::{self, AsyncRead, AsyncReadExt, AsyncSeek, AsyncSeekExt, ReadBuf, SeekFrom},
    join,
    sync::mpsc,
};
use tonic::Request;
use tracing::field;
use tracing_subscriber::EnvFilter;
use uuid::Uuid;

mod util;

const DOCKER_NS: &str = "moby";

#[derive(Debug, Snafu)]
enum Error {
    #[snafu(display("can't connect to containerd {}", path.display()))]
    ContainerdConnectError {
        path: PathBuf,
        source: tonic::transport::Error,
    },

    #[snafu(display("can't open archive \"{}\"", path.display()))]
    ArchiveOpenError { path: PathBuf, source: io::Error },

    #[snafu(display("error while parsing archive"))]
    ArchiveParseError { source: io::Error },

    #[snafu(display("can't read \"{path}\" (from archive)"))]
    ArchiveFileReadError { path: String, source: io::Error },

    #[snafu(display("failed to deserialize \"{path}\" (from archive)"))]
    ArchiveFileDeserializeError {
        path: String,
        source: serde_json::Error,
    },

    #[snafu(display("unsupported OCI layout version \"{version}\""))]
    UnsupportedOciLayoutVersion { version: String },

    #[snafu(display("unsupported OCI index schema version {version}"))]
    UnsupportedOciIndexSchemaVersion { version: u32 },

    #[snafu(display("failed to create lease"))]
    LeaseCreateError { source: GrpcError },

    #[snafu(display("no manifest for platform {platform}"))]
    NoManifest { platform: String },

    #[snafu(display("blob id {id} missing"))]
    MissingBlob { id: String },

    #[snafu(display("failed to upload blob {id}"))]
    BlobUploadError { id: String, source: BlobUploadError },
}

#[derive(Debug, Snafu)]
#[snafu(display("gRPC call {request} failed ({status})"))]
struct GrpcError {
    request: &'static str,
    status: tonic::Status,
}

#[derive(Debug, Snafu)]
enum BlobUploadError {
    #[snafu(transparent)]
    Io { source: io::Error },
    #[snafu(transparent)]
    Rpc { source: GrpcError },
}

#[derive(Parser)]
struct Options {
    file: PathBuf,

    /// containerd address
    #[arg(long, default_value = "/run/containerd/containerd.sock")]
    address: PathBuf,

    /// Set platform (e.g. linux/amd64, linux/arm64)
    #[arg(long, value_parser = parse_platform, default_value_t = default_platform())]
    platform: String,
}

fn parse_platform(s: &str) -> Result<String, String> {
    let invalid_value = || format!("invalid platform {s}");
    let invalid_chars = |c: char| !c.is_alphanumeric();
    let (os, arch) = s.split_once("/").ok_or_else(invalid_value)?;
    if os.find(invalid_chars).is_some() || arch.find(invalid_chars).is_some() {
        return Err(invalid_value());
    }
    Ok(s.to_string())
}

fn default_platform() -> String {
    format!("{}/{}", util::goos(), util::goarch())
}

#[tokio::main]
async fn main() -> eyre::Result<()> {
    let opts = Options::parse();
    tracing_subscriber::fmt()
        .with_writer(stderr)
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    run(opts).await?;
    Ok(())
}

async fn run(opts: Options) -> Result<(), Error> {
    let containerd = containerd_client::Client::from_path(&opts.address)
        .await
        .with_context(|_| ContainerdConnectSnafu {
            path: &opts.address,
        })?;
    let mut tar = File::open(&opts.file)
        .await
        .with_context(|_| ArchiveOpenSnafu {
            path: opts.file.clone(),
        })?;
    let mut tar_raw = tar.try_clone().await.unwrap();
    let tar = async_tar::Archive::new(&mut tar);
    process_archive(containerd, tar, &mut tar_raw, &opts.platform).await?;
    Ok(())
}

async fn process_archive<R: Debug + AsyncRead + AsyncSeek + Unpin>(
    containerd: containerd_client::Client,
    tar: Archive<&mut R>,
    tar_raw: &mut File,
    platform: &str,
) -> Result<(), Error> {
    struct FileMeta {
        offset: u64,
        size: u64,
    }

    let mut files = HashMap::new();
    let mut entries = tar.entries().context(ArchiveParseSnafu)?;
    while let Some(r) = entries.next().await {
        let entry = r.context(ArchiveParseSnafu)?;
        let path = match String::from_utf8(entry.path_bytes().to_vec()) {
            Ok(path) => path,
            Err(_) => {
                warn!("ignoring entry with invalid UTF-8");
                continue;
            }
        };
        if entry.header().entry_type() != EntryType::Regular {
            continue;
        }
        files.insert(
            path,
            FileMeta {
                offset: entry.raw_file_position(),
                size: entry.header().size().unwrap(),
            },
        );
    }

    async fn json_deserialize_from_file<T: DeserializeOwned, R: AsyncRead + AsyncSeek + Unpin>(
        archive: &mut R,
        files: &HashMap<String, FileMeta>,
        path: &str,
    ) -> Result<T, Error> {
        let entry = files.get(path).ok_or_else(|| {
            ArchiveFileReadSnafu { path }.into_error(io::ErrorKind::NotFound.into())
        })?;
        archive
            .seek(SeekFrom::Start(entry.offset))
            .await
            .with_context(|_| ArchiveFileReadSnafu { path })?;
        let mut data = vec![];
        archive
            .take(entry.size)
            .read_to_end(&mut data)
            .await
            .with_context(|_| ArchiveFileReadSnafu { path })?;
        serde_json::from_slice(&data[..]).with_context(|_| ArchiveFileDeserializeSnafu { path })
    }

    let layout: OciLayout = json_deserialize_from_file(tar_raw, &files, "oci-layout").await?;
    ensure!(
        layout.image_layout_version().starts_with("1."),
        UnsupportedOciLayoutVersionSnafu {
            version: layout.image_layout_version()
        }
    );

    // Not required by OCI spec
    let index: ImageIndex = json_deserialize_from_file(tar_raw, &files, "index.json").await?;
    ensure!(
        index.schema_version() == 2,
        UnsupportedOciIndexSchemaVersionSnafu {
            version: index.schema_version()
        }
    );
    for desc in index.manifests() {
        if *desc.media_type() != MediaType::ImageManifest {
            continue;
        }
        let digest = desc.digest();
        let manifest_path = format!("blobs/{}/{}", digest.algorithm(), digest.digest());

        let manifest: ImageManifest =
            match json_deserialize_from_file(tar_raw, &files, &manifest_path).await {
                Ok(manifest) => manifest,
                Err(error) => {
                    warn!(
                        error = field::display(error),
                        manifest_path, "can't read manifest, ignoring"
                    );
                    continue;
                }
            };
        if manifest.schema_version() != 2 {
            warn!(
                manifest_path,
                schema_version = manifest.schema_version(),
                "unsupported manifest schema version, ignoring"
            );
            continue;
        }
        let config_desc = manifest.config();
        if *config_desc.media_type() != MediaType::ImageConfig {
            warn!(
                "media-type" = field::display(config_desc.media_type()),
                "unsupported media-type for config descriptor, ignoring"
            );
            continue;
        }
        let config_path = format!(
            "blobs/{}/{}",
            config_desc.digest().algorithm(),
            config_desc.digest().digest()
        );
        let config: ImageConfiguration =
            match json_deserialize_from_file(tar_raw, &files, &config_path).await {
                Ok(config) => config,
                Err(error) => {
                    warn!(error = field::display(error), "can't read config, ignoring");
                    continue;
                }
            };
        let manifest_platform = format!("{}/{}", config.os(), config.architecture());
        if manifest_platform != platform {
            debug!("ignoring manifest with platform {manifest_platform}");
            continue;
        }
        info!("{platform} config: {config:?}");

        // TODO: fill name
        let image_name = "dupa";

        let mut content = containerd.content();
        let mut leases = containerd.leases();
        let lease = {
            let mut labels = HashMap::new();
            labels.insert(
                "containerd.io/gc.bref.image".to_string(),
                image_name.to_string(),
            );
            labels.insert(
                "containerd.io/gc.expire".to_string(),
                chrono::Utc::now().to_rfc3339(),
            );
            let lease_id = format!("nix-import-{}-{}", desc.digest().digest(), Uuid::new_v4());
            let resp = leases
                .create(with_namespace!(
                    CreateRequest {
                        id: lease_id,
                        labels,
                    },
                    DOCKER_NS
                ))
                .await
                .map_err(|status| GrpcError {
                    request: CreateRequest::NAME,
                    status,
                })
                .context(LeaseCreateSnafu)?;
            resp.into_inner().lease.unwrap()
        };

        let result = try {
            for layer in manifest.layers() {
                let layer_path = format!(
                    "blobs/{}/{}",
                    layer.digest().algorithm(),
                    layer.digest().digest()
                );
                if files.get(&layer_path).is_none() {
                    MissingBlobSnafu {
                        id: layer.digest().digest().to_string(),
                    }
                    .fail()?
                }
            }

            for layer in manifest.layers() {
                let layer_path = format!(
                    "blobs/{}/{}",
                    layer.digest().algorithm(),
                    layer.digest().digest()
                );
                let meta = files.get(&layer_path).unwrap();
                upload_blob(
                    &mut content,
                    &lease.id,
                    meta.offset,
                    tar_raw,
                    &layer.digest(),
                    meta.size,
                )
                .await
                .with_context(|_| BlobUploadSnafu {
                    id: layer.digest().digest(),
                })?;
            }
        };

        if let Err(status) = leases
            .delete(with_namespace!(
                DeleteRequest {
                    id: lease.id.clone(),
                    sync: false,
                },
                DOCKER_NS
            ))
            .await
        {
            warn!(
                status = field::display(status),
                id = lease.id,
                "failed to delete lease"
            );
        }

        result?;

        return Ok(());
    }

    Err(Error::NoManifest {
        platform: platform.to_string(),
    })
}

async fn upload_blob(
    content: &mut ContentClient<tonic::transport::Channel>,
    lease_id: &str,
    blob_offset: u64,
    blob: &mut File,
    blob_digest: &Digest,
    blob_size: u64,
) -> Result<(), BlobUploadError> {
    const CHUNK_SIZE: u64 = 16777384;

    let span = info_span!(
        "uploading blob",
        digest = field::display(blob_digest.digest()),
        size = blob_size,
        n_chunks = blob_size.div_ceil(CHUNK_SIZE),
    );
    let _guard = span.enter();

    blob.seek(SeekFrom::Start(blob_offset))
        .await
        .map_err(|source| BlobUploadError::Io { source })?;

    let (tx, mut rx) = mpsc::channel(1);
    let mut req = Request::new(futures_util::stream::poll_fn(move |cx| rx.poll_recv(cx)));
    let md = req.metadata_mut();
    md.insert("containerd-namespace", DOCKER_NS.parse().unwrap());
    md.insert("containerd-lease", lease_id.parse().unwrap());

    let upload_task = async {
        let r#ref = format!("{}", Uuid::new_v4());

        let mut left = blob_size;
        let mut offset = 0;
        let mut chunk = 0;

        if tx
            .send(WriteContentRequest {
                action: 0,
                r#ref,
                total: blob_size.try_into().unwrap(),
                expected: blob_digest.to_string(),
                offset: 0,
                data: vec![],
                labels: HashMap::new(),
            })
            .await
            .is_err()
        {
            error!("channel terminated during upload");
            return Ok(());
        }

        while left > 0 {
            debug!(i = chunk, "chunk");
            let mut buf = Vec::with_capacity(min(left as _, CHUNK_SIZE as _));
            let mut rb = ReadBuf::uninit(buf.spare_capacity_mut());
            let mut filled_old = rb.filled().len();

            while rb.remaining() > 0 {
                blob.read_buf(&mut rb).await?;
                if filled_old == rb.filled().len() {
                    return Err(io::ErrorKind::UnexpectedEof.into());
                }
                filled_old = rb.filled().len();
            }

            // Safety: data has been initialized
            unsafe { buf.set_len(filled_old) };
            if tx
                .send(WriteContentRequest {
                    action: WriteAction::Write as _,
                    r#ref: String::new(),
                    total: 0,
                    expected: String::new(),
                    offset: offset as _,
                    data: buf,
                    labels: HashMap::new(),
                })
                .await
                .is_err()
            {
                error!("channel terminated during upload");
                return Ok(());
            }

            left -= filled_old as u64;
            offset += filled_old as u64;
            chunk += 1;
        }
        if tx
            .send(WriteContentRequest {
                action: WriteAction::Commit as _,
                r#ref: String::new(),
                total: 0,
                expected: String::new(),
                offset: blob_size.try_into().unwrap(),
                data: vec![],
                labels: HashMap::new(),
            })
            .await
            .is_err()
        {
            error!("channel terminated during upload");
        }
        Result::<_, io::Error>::Ok(())
    };
    let resp_process = async {
        let resp = match content.write(req).await {
            Ok(resp) => resp,
            Err(status) if status.code() == tonic::Code::AlreadyExists => {
                info!("blob already exists");
                return Ok(());
            }
            Err(status) => return Err(status),
        };
        let mut resp_stream = resp.into_inner();
        loop {
            match resp_stream.message().await {
                Ok(Some(_)) => {}
                Ok(None) => {
                    info!("upload complete");
                    break;
                }
                Err(status) => {
                    return Err(status);
                }
            }
        }

        Result::<_, tonic::Status>::Ok(())
    };
    let (x, y) = join!(upload_task, resp_process);
    x.map_err(|source| BlobUploadError::Io { source })?;
    y.map_err(|status| BlobUploadError::Rpc {
        source: GrpcError {
            request: WriteContentRequest::NAME,
            status,
        },
    })?;

    Ok(())
}
*/
