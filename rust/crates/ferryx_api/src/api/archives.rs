//! Archives before they are entered or extracted: what one holds and the
//! password it asks for.

use std::path::Path;

use ferryx_vfs::archive::{self, shared, ArchiveFormat, Compression};
use ferryx_vfs::VfsErrorKind;

use crate::api::types::ApiResult;
use crate::app;

/// One installed command-line engine; adapters are fixed, never shell templates.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArchiverView {
    pub name: String,
    pub path: String,
    pub engine: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ArchiverOptionsView {
    pub level: Option<u32>,
    pub threads: Option<u32>,
    pub solid: Option<bool>,
    pub arguments: Vec<String>,
}

impl ArchiverOptionsView {
    fn to_ops(&self) -> ferryx_ops::archivers::Options {
        ferryx_ops::archivers::Options {
            level: self.level,
            threads: self.threads,
            solid: self.solid,
            arguments: self.arguments.clone(),
        }
    }
}

pub fn validate_archiver_options(engine: Option<String>, options: ArchiverOptionsView) -> ApiResult<()> {
    let engine = engine
        .map(|name| {
            ferryx_ops::archivers::Engine::parse(&name)
                .ok_or_else(|| ferryx_vfs::VfsError::unsupported("Unknown archiver adapter"))
        })
        .transpose()?;
    options.to_ops().validate(engine).map_err(|error| ferryx_vfs::VfsError::unsupported(&error))?;
    Ok(())
}

pub fn start_configured_zip(
    request: super::types::OpRequestView,
    options: ArchiverOptionsView,
) -> ApiResult<i64> {
    options.to_ops().validate(None).map_err(|error| ferryx_vfs::VfsError::unsupported(&error))?;
    Ok(ferryx_ops::archivers::start_configured_zip(app::runner(), request.to_ops(), options.to_ops()) as i64)
}

/// Runs on a bridge worker. Filesystem-only detection also checks common
/// package-manager locations absent from a macOS GUI launch's PATH.
pub fn discover_archivers(manual: Vec<ArchiverView>) -> Vec<ArchiverView> {
    let manual = manual.into_iter().filter_map(tool_from_view).collect();
    ferryx_ops::archivers::catalog::discover(manual)
        .into_iter()
        .map(|tool| ArchiverView {
            name: tool.name,
            path: tool.path.to_string_lossy().into_owned(),
            engine: tool.engine.name().into(),
        })
        .collect()
}

fn tool_from_view(view: ArchiverView) -> Option<ferryx_ops::archivers::Tool> {
    Some(ferryx_ops::archivers::Tool {
        name: view.name,
        path: view.path.into(),
        engine: ferryx_ops::archivers::Engine::parse(&view.engine)?,
    })
}

/// Uses the normal operation stream, cancellation, conflicts and Undo journal.
pub fn start_external_archive(
    request: super::types::OpRequestView,
    tool: ArchiverView,
    format: String,
    options: ArchiverOptionsView,
) -> ApiResult<i64> {
    let tool =
        tool_from_view(tool).ok_or_else(|| ferryx_vfs::VfsError::unsupported("Unknown archiver adapter"))?;
    options
        .to_ops()
        .validate(Some(tool.engine))
        .map_err(|error| ferryx_vfs::VfsError::unsupported(&error))?;
    Ok(ferryx_ops::archivers::start_with_options(
        app::runner(),
        request.to_ops(),
        tool,
        format,
        options.to_ops(),
    ) as i64)
}

/// What Extract To needs to know about an archive before it asks.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArchiveInfoView {
    /// `zip`, `tar.gz`, `7z`, `rar`, `iso`, `gz`… as the format is known.
    pub format: String,
    /// The members at the archive's root: one means the archive unpacks
    /// to one item, more that it wants a folder of its own.
    pub top_level_count: i64,
    /// The name of the one member at the root, when there is one.
    pub single_top_level: Option<String>,
    pub file_count: i64,
    /// Bytes of the files unpacked (what the format says).
    pub unpacked_bytes: i64,
    /// Some member's data is encrypted.
    pub encrypted: bool,
    /// The member list itself is encrypted and no password opened it yet:
    /// the counts are unknown until one does.
    pub needs_password: bool,
    /// A password was given for this archive and opened it.
    pub has_password: bool,
}

/// What the archive at `path` holds; an encrypted member list answers
/// `needs_password` rather than an error.
pub fn archive_info(path: String) -> ApiResult<ArchiveInfoView> {
    let path = Path::new(&path);
    let has_password = shared::password(path).is_some();
    let index = match app::archive_index(path) {
        Ok(index) => index,
        Err(e) if e.kind == VfsErrorKind::PasswordRequired => {
            let format = archive::detect(path)?.map(format_name).unwrap_or_default();
            return Ok(ArchiveInfoView {
                format,
                top_level_count: 0,
                single_top_level: None,
                file_count: 0,
                unpacked_bytes: 0,
                encrypted: true,
                needs_password: true,
                has_password,
            });
        }
        Err(e) => return Err(e.into()),
    };
    let top: Vec<_> = index.top_level().collect();
    let (bytes, files) = index.totals(&[String::new()]);
    Ok(ArchiveInfoView {
        format: format_name(index.format),
        top_level_count: top.len() as i64,
        single_top_level: if top.len() == 1 { Some(top[0].name().to_string()) } else { None },
        file_count: files as i64,
        unpacked_bytes: bytes as i64,
        encrypted: index.encrypted,
        needs_password: false,
        has_password,
    })
}

/// Tries `password` on the archive and keeps it for its listings, its
/// viewer and its extractions when it opens it; a wrong one is a
/// `WrongPassword` error.
pub fn set_archive_password(archive: String, password: String) -> ApiResult<()> {
    Ok(shared::set_password(Path::new(&archive), &password)?)
}

/// Whether the file at `path` is an archive by its first bytes or its
/// name (⌘↓ opens any file it says yes to).
pub fn detect_archive(path: String) -> bool {
    matches!(archive::detect(Path::new(&path)), Ok(Some(_)))
}

fn format_name(format: ArchiveFormat) -> String {
    let compression = |c: Compression| match c {
        Compression::None => "",
        Compression::Gzip => "gz",
        Compression::Bzip2 => "bz2",
        Compression::Xz => "xz",
        Compression::Zstd => "zst",
    };
    match format {
        ArchiveFormat::Zip => "zip".to_string(),
        ArchiveFormat::Tar(Compression::None) => "tar".to_string(),
        ArchiveFormat::Tar(c) => format!("tar.{}", compression(c)),
        ArchiveFormat::SevenZip => "7z".to_string(),
        ArchiveFormat::Rar => "rar".to_string(),
        ArchiveFormat::Iso => "iso".to_string(),
        ArchiveFormat::Single(c) => compression(c).to_string(),
    }
}
