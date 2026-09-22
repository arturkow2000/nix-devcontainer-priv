#[macro_use]
extern crate tracing;

#[macro_use]
extern crate snafu;

mod util;

use std::{
    collections::HashMap,
    fmt::{self, Debug},
    io::{SeekFrom, stderr},
    path::PathBuf,
    pin::Pin,
};

use async_tar::{Archive, EntryType};
use clap::{Args, Parser};
use const_format::concatcp;
use containerd_client::{
    services::v1::{
        CreateImageRequest, CreateRequest, DeleteRequest, Image, TransferRequest,
        images_client::ImagesClient, streaming_client::StreamingClient,
        transfer_client::TransferClient,
    },
    types::{
        Platform,
        transfer::{ImageImportStream, ImageStore, UnpackConfiguration},
    },
    with_namespace,
};
use futures_util::StreamExt;
use oci_spec::image::{ImageConfiguration, ImageIndex, ImageManifest, MediaType, OciLayout};
use prost::{Message, Name};
use prost_types::Any;
use serde::de::DeserializeOwned;
use sha2::Digest as _;
use snafu::{IntoError as _, ResultExt};
use tokio::{
    fs::File,
    io::{self, AsyncRead, AsyncReadExt as _, AsyncSeek, AsyncSeekExt as _},
    join,
};
use tonic::{
    Extensions, Request,
    metadata::{MetadataMap, MetadataValue},
};
use tracing::field;
use tracing_subscriber::EnvFilter;
use uuid::Uuid;

use crate::util::{GrpcError, UploadError};

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

    #[command(flatten)]
    tag: TagOptions,
}

#[derive(Args)]
#[group(multiple = false)]
struct TagOptions {
    /// Import as untagged image.
    #[arg(long)]
    no_tag: bool,

    /// Import with custom tag.
    #[arg(long)]
    tag: Option<String>,
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
    ContainerdConnect {
        path: PathBuf,
        source: tonic::transport::Error,
    },

    #[snafu(display("can't open archive \"{}\"", path.display()))]
    ArchiveOpen { path: PathBuf, source: io::Error },

    #[snafu(display("error while parsing archive"))]
    ArchiveParse { source: io::Error },

    #[snafu(display("can't read \"{path}\" (from archive)"))]
    ArchiveFileRead { path: String, source: io::Error },

    #[snafu(display("failed to deserialize \"{path}\" (from archive)"))]
    ArchiveFileDeserialize {
        path: String,
        source: serde_json::Error,
    },

    #[snafu(display("unsupported OCI layout version \"{version}\""))]
    UnsupportedOciLayoutVersion { version: String },

    #[snafu(display("unsupported OCI index schema version {version}"))]
    UnsupportedOciIndexSchemaVersion { version: u32 },

    #[snafu(display("failed to create lease"))]
    LeaseCreate { source: GrpcError },

    #[snafu(display("no manifest for platform {platform}"))]
    NoManifest { platform: String },

    #[snafu(display("blob id {id} missing"))]
    MissingBlob { id: String },

    #[snafu(display("failed to upload archive"))]
    Upload { source: UploadError },

    #[snafu(display("can't create image reference \"{name}\""))]
    RefCreate { name: String, source: GrpcError },
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

    let result = upload_tar(
        &containerd,
        tar,
        &mut tar_raw,
        &opts.platform,
        &lease.id,
        &opts.tag,
    )
    .await;

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
    tag: &TagOptions,
) -> Result<(), Error> {
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

    let layout: OciLayout = json_deserialize_from_file(tar_raw, &files, "oci-layout").await?;
    ensure!(
        layout.image_layout_version().starts_with("1."),
        UnsupportedOciLayoutVersionSnafu {
            version: layout.image_layout_version()
        }
    );

    let index_raw = read_tar_file(tar_raw, &files, "index.json").await?;
    let index_digest = {
        let mut hasher = sha2::Sha256::new();
        hasher.update(&index_raw);
        hasher.finalize()
    };

    let index: ImageIndex = serde_json::from_slice(&index_raw)
        .with_context(|_| ArchiveFileDeserializeSnafu { path: "index.json" })?;
    ensure!(
        index.schema_version() == 2,
        UnsupportedOciIndexSchemaVersionSnafu {
            version: index.schema_version()
        }
    );

    let name = if tag.no_tag {
        format!("moby-dangling@sha256:{}", hexstring(&index_digest))
    } else if let Some(tag) = tag.tag.clone() {
        tag
    } else {
        get_tag(&index, &files, tar_raw, platform)
            .await
            .unwrap_or_else(|| format!("moby-dangling@sha256:{}", hexstring(&index_digest)))
    };

    let mut streaming = containerd.streaming();
    let mut transfer = containerd.transfer();
    let mut images = containerd.images();

    // Stream entire tar to containerd.
    tar_raw
        .seek(SeekFrom::Start(0))
        .await
        .map_err(|source| Error::Upload {
            source: UploadError::Io { source },
        })?;
    upload_tar_and_create_ref(
        &mut streaming,
        &mut transfer,
        &mut images,
        tar_raw,
        Some(&name),
        platform,
        lease,
        index.media_type().clone().unwrap_or(MediaType::ImageIndex),
        &index_digest,
        index_raw.len(),
        index.annotations().clone().unwrap_or_default(),
    )
    .await?;

    Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn upload_tar_and_create_ref<R: AsyncRead + Unpin>(
    streaming: &mut StreamingClient<tonic::transport::Channel>,
    transfer: &mut TransferClient<tonic::transport::Channel>,
    images: &mut ImagesClient<tonic::transport::Channel>,
    archive: &mut R,
    name: Option<&str>,
    platform: &str,
    lease: &str,
    media_type: MediaType,
    index_digest: &[u8],
    index_size: usize,
    annotations: HashMap<String, String>,
) -> Result<(), Error> {
    upload_archive(streaming, transfer, archive, platform, lease)
        .await
        .context(UploadSnafu {})?;

    let name = name.map_or_else(
        || format!("moby-dangling@sha256:{}", hexstring(index_digest)),
        |name| {
            let no_prefix = name
                .strip_prefix("docker.io/library/")
                .map_or_else(|| name.to_string(), str::to_string);
            let (no_prefix_no_ver, ver) =
                if let Some((no_prefix_no_ver, ver)) = no_prefix.split_once(":") {
                    (no_prefix_no_ver, ver)
                } else {
                    (no_prefix.as_str(), "latest")
                };
            format!("docker.io/library/{no_prefix_no_ver}:{ver}")
        },
    );

    info!("saving as {name}");

    // Create the reference.
    // At this point image becomes visible in `docker image ls`. Reference becomes new, permanent
    // gc root so content isn't garbage collected.
    images
        .create(with_namespace!(
            CreateImageRequest {
                image: Some(Image {
                    name: name.clone(),
                    labels: HashMap::new(),
                    target: Some(containerd_client::types::Descriptor {
                        media_type: media_type.to_string(),
                        digest: format!("sha256:{}", hexstring(index_digest)),
                        size: index_size as _,
                        annotations,
                    }),
                    created_at: None,
                    updated_at: None,
                }),
                source_date_epoch: None,
            },
            DOCKER_NS
        ))
        .await
        .map_err(|status| Error::RefCreate {
            name,
            source: GrpcError {
                request: concatcp!(CreateImageRequest::PACKAGE, ".", CreateImageRequest::NAME),
                status,
            },
        })?;
    Ok(())
}

async fn upload_archive<R: AsyncRead + Unpin>(
    streaming: &mut StreamingClient<tonic::transport::Channel>,
    transfer: &mut TransferClient<tonic::transport::Channel>,
    archive: &mut R,
    platform: &str,
    lease: &str,
) -> Result<(), UploadError> {
    let meta = {
        let mut meta = MetadataMap::new();
        meta.insert(
            "containerd-namespace",
            MetadataValue::from_static(DOCKER_NS),
        );
        meta.insert("containerd-lease", lease.parse().unwrap());
        meta
    };
    let stream_id = Uuid::new_v4();
    let stream =
        util::ContainerdStreamingChannel::new(streaming, stream_id.to_string(), meta.clone())
            .await
            .map_err(|source| UploadError::Grpc { source })?;
    let mut sink = stream.new_sink();
    let wait = stream.wait_init();
    let copy_task = async move {
        // use async move so sink gets dropped after copy
        util::copy_to_containerd(Pin::new(archive), &mut sink).await
    };
    // Upload entire tar archive to containerd.
    // At this point we deliberately don't create image reference (empty name and extra_references)
    // because we can't control how those references are created.
    // Docker requires single reference to OCI index but containerd creates one reference to index and
    // another to manifest, causing duplicate entries `docker image ls` and inability to actually use the
    // for anything (both by name and by hash).
    //
    // Upload is bound to our lease which acts as temporary gc root, containerd will automatically remove the content
    // if creating reference fails for whatever reason.
    let transfer_task = async move {
        wait.await?;
        let (os, arch) = platform.split_once("/").unwrap();
        let req = Request::from_parts(
            meta,
            Extensions::new(),
            TransferRequest {
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
                        extra_references: vec![],
                        // This part is critical.
                        // Unpack using nix-snapshotter, this is when gcroots are created
                        // so nix doesn't remove our data on next nix-collect-garbage.
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
            },
        );
        transfer.transfer(req).await.map_err(|status| GrpcError {
            request: concatcp!(TransferRequest::PACKAGE, ".", TransferRequest::NAME),
            status,
        })?;

        Result::<_, GrpcError>::Ok(())
    };
    let (x, y, z) = join!(copy_task, transfer_task, stream.process());
    x?;
    y?;
    z?;

    Ok(())
}

fn hexstring(bytes: &[u8]) -> impl fmt::Display {
    fmt::from_fn(move |f| {
        for &b in bytes {
            write!(f, "{b:02x}")?;
        }
        Ok(())
    })
}

struct FileMeta {
    offset: u64,
    size: u64,
}

async fn read_tar_file<R: AsyncRead + AsyncSeek + Unpin>(
    archive: &mut R,
    files: &HashMap<String, FileMeta>,
    path: &str,
) -> Result<Vec<u8>, Error> {
    let entry = files
        .get(path)
        .ok_or_else(|| ArchiveFileReadSnafu { path }.into_error(io::ErrorKind::NotFound.into()))?;
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
    Ok(data)
}
async fn json_deserialize_from_file<T: DeserializeOwned, R: AsyncRead + AsyncSeek + Unpin>(
    archive: &mut R,
    files: &HashMap<String, FileMeta>,
    path: &str,
) -> Result<T, Error> {
    let data = read_tar_file(archive, files, path).await?;
    serde_json::from_slice(&data[..]).with_context(|_| ArchiveFileDeserializeSnafu { path })
}

async fn get_tag<R: AsyncRead + AsyncSeek + Unpin>(
    index: &ImageIndex,
    files: &HashMap<String, FileMeta>,
    tar_raw: &mut R,
    platform: &str,
) -> Option<String> {
    fn _get_tag(annotations: &HashMap<String, String>) -> Option<&str> {
        annotations
            .get("io.containerd.image.name")
            .or_else(|| annotations.get("org.opencontainers.image.ref."))
            .map(String::as_str)
    }

    for desc in index.manifests() {
        let has_name = desc
            .annotations()
            .as_ref()
            .unwrap_or(&HashMap::new())
            .iter()
            .any(|(k, _)| {
                k == "io.containerd.image.name" || k == "org.opencontainers.image.ref.name"
            });
        if !has_name {
            continue;
        }

        // We need to extract manifest then config, that is where manifest's platform is defined.
        let manifest_path = format!(
            "blobs/{}/{}",
            desc.digest().algorithm(),
            desc.digest().digest()
        );
        let manifest: ImageManifest =
            match json_deserialize_from_file(tar_raw, files, &manifest_path).await {
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
            match json_deserialize_from_file(tar_raw, files, &config_path).await {
                Ok(config) => config,
                Err(error) => {
                    warn!(error = field::display(error), "can't read config, ignoring");
                    continue;
                }
            };
        if format!("{}/{}", config.os(), config.architecture()).to_lowercase()
            == platform.to_lowercase()
        {
            return _get_tag(desc.annotations().as_ref().unwrap_or(&HashMap::new()))
                .map(str::to_string);
        }
    }

    None
}
