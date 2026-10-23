//! Folders on servers: SFTP, FTP with explicit FTPS, and WebDAV over
//! HTTP(S), behind one trait ([`RemoteFs`]) that the listings and the
//! operations use the same way whatever the protocol.
//!
//! - [`address`]: a server's address and key, paths on it.
//! - [`connection`]: the open servers, one per key, with their state
//!   (connected, lost, closed) reported to a listener.
//! - [`sftp`], [`ftp`], [`webdav`]: the three protocols.
//! - [`known_hosts`], [`prompt`], [`secrets`], [`tls`]: SSH host keys, the
//!   questions a connection asks the user, the keychain, certificates.
//! - [`runtime`]: the runtime the network code runs on, deadlines and
//!   stops.
//!
//! Every call blocks its caller (a listing on a worker of the bridge, an
//! operation on its own thread), has a deadline and stops when asked;
//! errors carry a kind the interface words (`AuthFailed`,
//! `HostUnreachable`, `TimedOut`, `HostKeyChanged`…).

pub mod address;
mod blocking;
pub mod connection;
mod entries;
pub mod ftp;
mod ftp_list;
pub mod known_hosts;
pub mod prompt;
pub mod runtime;
pub mod secrets;
pub mod sftp;
pub mod tls;
pub mod webdav;

pub use address::{Protocol, ServerAddress};
pub use connection::{AuthMethod, ConnState, ConnectSpec, Server};
pub use runtime::{never, Stop};

use ferryx_core::entry::Entry;

use crate::error::{VfsError, VfsErrorKind, VfsResult};

/// What a server's protocol can do beyond reading and writing files.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RemoteCaps {
    /// A file's modification time can be set (SFTP, FTP with `MFMT`).
    pub set_modified: bool,
    /// Items can be copied on the server itself (WebDAV `COPY`).
    pub server_copy: bool,
    /// Removing a folder removes what it holds (WebDAV `DELETE`).
    pub recursive_delete: bool,
}

/// One server's files. Paths are absolute and `/`-separated, as the
/// server spells them. Each call blocks until the server answers, the
/// deadline passes or `stop` says to stop.
pub trait RemoteFs: Send + Sync {
    /// The folder the server starts in: the home folder over SFTP and
    /// FTP, the address's folder over WebDAV.
    fn home(&self) -> String;

    fn caps(&self) -> RemoteCaps;

    /// The rows of the folder `dir`, unsorted, hidden ones included,
    /// without `.` and `..`. Each row's path is its path on the server.
    fn list(&self, dir: &str, stop: Stop) -> VfsResult<Vec<Entry>>;

    /// The item at `path` (not following a symbolic link); `None` when
    /// there is none.
    fn stat(&self, path: &str, stop: Stop) -> VfsResult<Option<Entry>>;

    /// Up to `len` bytes of the file at `path` from `offset`; fewer only
    /// at its end.
    fn read_range(&self, path: &str, offset: u64, len: usize, stop: Stop) -> VfsResult<Vec<u8>>;

    /// The file at `path` to read from its start, as a stream.
    fn open_read<'a>(&'a self, path: &str, stop: Stop) -> VfsResult<Box<dyn RemoteRead + 'a>>;

    /// A new file at `path`, replacing one there, written as a stream;
    /// `size` (when known) lets HTTP send it with its length.
    fn create<'a>(
        &'a self,
        path: &str,
        size: Option<u64>,
        stop: Stop,
    ) -> VfsResult<Box<dyn RemoteWrite + 'a>>;

    /// A new folder at `path`; [`VfsErrorKind::AlreadyExists`] when an item
    /// is there.
    fn mkdir(&self, path: &str, stop: Stop) -> VfsResult<()>;

    /// Renames or moves the item at `from` to `to`, on this server; fails
    /// when `to` is taken.
    fn rename(&self, from: &str, to: &str, stop: Stop) -> VfsResult<()>;

    fn remove_file(&self, path: &str, stop: Stop) -> VfsResult<()>;

    /// Removes the empty folder at `path`.
    fn remove_dir(&self, path: &str, stop: Stop) -> VfsResult<()>;

    /// Sets the modification time of `path` (Unix milliseconds); see
    /// [`RemoteCaps::set_modified`].
    fn set_modified(&self, path: &str, modified_ms: i64, stop: Stop) -> VfsResult<()> {
        let _ = (path, modified_ms, stop);
        Err(VfsError::unsupported("this server cannot set a file's time"))
    }

    /// Copies the item at `from` to `to` on the server itself; see
    /// [`RemoteCaps::server_copy`].
    fn copy(&self, from: &str, to: &str, stop: Stop) -> VfsResult<()> {
        let _ = (from, to, stop);
        Err(VfsError::unsupported("this server cannot copy on its own"))
    }

    /// Opens the connection again (after it dropped), asking the user
    /// again only what was not kept.
    fn reconnect(&self, stop: Stop) -> VfsResult<()>;

    /// Closes every connection to the server.
    fn close(&self);

    /// Closes connections idle for a while (an FTP control connection
    /// per transfer); called now and then.
    fn reap_idle(&self) {}
}

/// A file being read from a server.
pub trait RemoteRead {
    /// Reads into `buf`; 0 at the end.
    fn read(&mut self, buf: &mut [u8], stop: Stop) -> VfsResult<usize>;
}

/// A file being written to a server. Dropped without
/// [`RemoteWrite::finish`], the transfer is abandoned (what reached the
/// server may stay there).
pub trait RemoteWrite {
    fn write_all(&mut self, data: &[u8], stop: Stop) -> VfsResult<()>;

    /// Ends the transfer and waits for the server to have it all.
    fn finish(self: Box<Self>, stop: Stop) -> VfsResult<()>;
}

/// A path that cannot be on a server: relative, or with a part a server
/// would read as a separator or a command.
pub fn check_path(path: &str) -> VfsResult<()> {
    if !path.starts_with('/') || path.contains('\0') || path.contains('\n') || path.contains('\r') {
        return Err(VfsError::remote(
            VfsErrorKind::InvalidName,
            Some(path),
            format!("“{path}” is not a path on the server"),
        ));
    }
    Ok(())
}
