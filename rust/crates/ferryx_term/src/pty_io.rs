//! Reading and writing the pseudo-terminal's master side so that a closing
//! session never hangs a thread.
//!
//! On Unix both ends are our own duplicates of the master descriptor in
//! non-blocking mode, waited on with `poll` (`select` on macOS, through
//! `filedescriptor`) in short slices that look at the stop flag: a
//! background job holding the terminal open after its shell died cannot
//! keep the reader blocked. Portable-pty's own writer is not used: dropped,
//! it types a newline and EOF, which would run a half-typed line.

use std::io;
use std::sync::atomic::{AtomicBool, Ordering};

/// The shell's output, read in chunks.
pub trait OutputSource: Send {
    /// Up to `buf.len()` bytes; `Ok(0)` once the terminal is closed or
    /// `stop` is set.
    fn read(&mut self, buf: &mut [u8], stop: &AtomicBool) -> io::Result<usize>;
}

/// The shell's input.
pub trait InputSink: Send {
    /// Writes all of `data` unless `stop` is set first.
    fn write_all(&mut self, data: &[u8], stop: &AtomicBool) -> io::Result<()>;
}

#[cfg(unix)]
pub use unix::source_and_sink;

#[cfg(unix)]
mod unix {
    use super::*;
    use filedescriptor::{poll, pollfd, FileDescriptor, POLLIN, POLLOUT};
    use std::io::{Read, Write};
    use std::os::fd::{BorrowedFd, RawFd};
    use std::time::Duration;

    /// How long a wait lasts before the stop flag is looked at again.
    const SLICE: Duration = Duration::from_millis(100);

    pub struct UnixSource(FileDescriptor);
    pub struct UnixSink(FileDescriptor);

    /// A reader and a writer over duplicates of `master`, which is put in
    /// non-blocking mode (a property every duplicate shares).
    pub fn source_and_sink(master: RawFd) -> io::Result<(UnixSource, UnixSink)> {
        // SAFETY: `master` is open for as long as the session holds the pty.
        let borrowed = unsafe { BorrowedFd::borrow_raw(master) };
        let mut read = FileDescriptor::dup(&borrowed).map_err(io::Error::other)?;
        let write = FileDescriptor::dup(&borrowed).map_err(io::Error::other)?;
        read.set_non_blocking(true).map_err(io::Error::other)?;
        Ok((UnixSource(read), UnixSink(write)))
    }

    /// Waits up to [`SLICE`] for `events` on `fd`; whether they came.
    fn wait(fd: &FileDescriptor, events: i16) -> io::Result<bool> {
        use std::os::fd::AsRawFd;
        let raw = fd.as_raw_fd();
        // `select`, which stands in for `poll` on macOS, takes descriptors
        // below FD_SETSIZE only: past it, a short sleep keeps the loop.
        if cfg!(target_os = "macos") && raw >= libc::FD_SETSIZE as RawFd {
            std::thread::sleep(Duration::from_millis(4));
            return Ok(false);
        }
        let mut fds = [pollfd { fd: raw, events, revents: 0 }];
        match poll(&mut fds, Some(SLICE)) {
            Ok(0) => Ok(false),
            Ok(_) => Ok(true),
            Err(e) => match e {
                filedescriptor::Error::Poll(err) if err.kind() == io::ErrorKind::Interrupted => Ok(false),
                other => Err(io::Error::other(other)),
            },
        }
    }

    impl OutputSource for UnixSource {
        fn read(&mut self, buf: &mut [u8], stop: &AtomicBool) -> io::Result<usize> {
            loop {
                if stop.load(Ordering::SeqCst) {
                    return Ok(0);
                }
                match self.0.read(buf) {
                    Ok(n) => return Ok(n),
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                        wait(&self.0, POLLIN)?;
                    }
                    Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
                    // EIO: the last process holding the terminal closed it.
                    Err(e) if e.raw_os_error() == Some(libc::EIO) => return Ok(0),
                    Err(e) => return Err(e),
                }
            }
        }
    }

    impl InputSink for UnixSink {
        fn write_all(&mut self, mut data: &[u8], stop: &AtomicBool) -> io::Result<()> {
            while !data.is_empty() {
                if stop.load(Ordering::SeqCst) {
                    return Ok(());
                }
                match self.0.write(data) {
                    Ok(0) => return Err(io::ErrorKind::WriteZero.into()),
                    Ok(n) => data = &data[n..],
                    // The program does not read its input: wait for room.
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                        wait(&self.0, POLLOUT)?;
                    }
                    Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
                    Err(e) => return Err(e),
                }
            }
            Ok(())
        }
    }
}

/// Portable-pty's own reader and writer, for ConPTY: closing the pseudo
/// console ends the reader there.
#[cfg(windows)]
pub struct BlockingSource(pub Box<dyn io::Read + Send>);

#[cfg(windows)]
pub struct BlockingSink(pub Box<dyn io::Write + Send>);

#[cfg(windows)]
impl OutputSource for BlockingSource {
    fn read(&mut self, buf: &mut [u8], stop: &AtomicBool) -> io::Result<usize> {
        if stop.load(Ordering::SeqCst) {
            return Ok(0);
        }
        self.0.read(buf)
    }
}

#[cfg(windows)]
impl InputSink for BlockingSink {
    fn write_all(&mut self, data: &[u8], stop: &AtomicBool) -> io::Result<()> {
        if stop.load(Ordering::SeqCst) {
            return Ok(());
        }
        self.0.write_all(data)?;
        self.0.flush()
    }
}
