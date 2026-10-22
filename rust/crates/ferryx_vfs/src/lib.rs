//! Everything Ferryx reads from and writes to the file system, behind
//! plain functions and a few handles. No bridge types; the one piece of
//! global state is the archive cache ([`archive::shared`]).
//!
//! - [`native`]: a folder's rows with their metadata, a file's bytes.
//! - [`archive`]: the members of an archive (zip, tar, 7z, rar, iso, a
//!   compressed file) as a read-only folder, read back streaming.
//! - [`location`]: where a panel is, on disk or inside an archive.
//! - [`watch`]: a folder watched for changes.
//! - [`flat`]: a folder's whole subtree as one list of files, in batches.
//! - [`volumes`], [`system`]: the disks, the standard folders, opening,
//!   revealing, the trash.
//! - [`tags`]: Finder tags, read with each item and written (macOS).
//! - [`attrs`], [`links`]: permissions, flags, owners, times; symbolic and
//!   hard links.
//! - [`trash`]: the trash with a receipt per item, to put it back.
//! - [`remote`]: folders on servers over SFTP, FTP and WebDAV.

pub mod archive;
pub mod attrs;
pub mod error;
pub mod flat;
pub mod links;
pub mod location;
pub mod native;
pub mod system;
pub mod tags;
pub mod trash;
pub mod volumes;
pub mod watch;
// ─── Network ───
pub mod remote;

pub use error::{VfsError, VfsErrorKind};
pub use ferryx_core::entry::{Entry, EntryKind};
pub use location::Location;
