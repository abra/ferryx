//! Everything Ferryx reads from and writes to the file system, behind
//! plain functions and a few handles. No bridge types, no global state.
//!
//! - [`native`]: a folder's rows with their metadata, a file's bytes.
//! - [`archive`]: the members of a zip or tar as a read-only folder.
//! - [`location`]: where a panel is, on disk or inside an archive.
//! - [`watch`]: a folder watched for changes.
//! - [`volumes`], [`system`]: the disks, the standard folders, opening,
//!   revealing, the trash.
//! - [`attrs`], [`links`]: permissions, flags, owners, times; symbolic and
//!   hard links.

pub mod archive;
pub mod attrs;
pub mod error;
pub mod links;
pub mod location;
pub mod native;
pub mod system;
pub mod volumes;
pub mod watch;

pub use error::{VfsError, VfsErrorKind};
pub use ferryx_core::entry::{Entry, EntryKind};
pub use location::Location;
