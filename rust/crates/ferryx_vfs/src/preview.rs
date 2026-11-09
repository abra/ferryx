//! Local paths lent to document decoders. Only privately staged copies
//! belong to the lease; a native source is never removed.

use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use parking_lot::Mutex;
use tempfile::TempDir;

use crate::archive::shared;
use crate::error::{IoAt, VfsError, VfsResult};
use crate::remote::{connection, RemoteRead, Stop};
use crate::Location;

const COPY_BUFFER: usize = 64 * 1024;

pub struct PreviewFile {
    location: Location,
    cancelled: AtomicBool,
    state: Mutex<State>,
}

enum State {
    Pending,
    Ready(Prepared),
    Failed(VfsError),
    Closed,
}

struct Prepared {
    path: PathBuf,
    directory: Option<TempDir>,
}

impl Prepared {
    fn close(self) -> VfsResult<()> {
        if let Some(directory) = self.directory {
            let path = directory.path().to_owned();
            directory.close().at(&path)?;
        }
        Ok(())
    }
}

impl PreviewFile {
    /// Allocates ownership before any I/O; preparation starts on demand.
    pub fn new(location: Location) -> Self {
        Self { location, cancelled: AtomicBool::new(false), state: Mutex::new(State::Pending) }
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }

    fn stopped(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }

    pub fn prepare(&self) -> VfsResult<PathBuf> {
        self.prepare_with(|| match &self.location {
            Location::Native(path) => Ok(Prepared { path: path.clone(), directory: None }),
            Location::Archive { archive, inner } => {
                let index = shared::index(archive)?;
                let password = shared::password(archive);
                stage(&self.location.name(), &|| self.stopped(), |file, _| {
                    index.read_member_to_until(inner, password.as_deref(), file, &|| self.stopped())?;
                    Ok(())
                })
            }
            Location::Remote { server, path } => {
                let server = connection::get(server)?;
                let stop = || self.stopped();
                let mut reader = server.fs().open_read(path, &stop)?;
                stage(&self.location.name(), &stop, |file, local| {
                    copy_remote(reader.as_mut(), file, local, &stop)
                })
            }
        })
    }

    fn prepare_with(&self, create: impl FnOnce() -> VfsResult<Prepared>) -> VfsResult<PathBuf> {
        // A second request shares the completed path; close waits for this
        // owner while cancellation remains independent of its lock.
        let mut state = self.state.lock();
        check(&|| self.stopped())?;
        if matches!(*state, State::Pending) {
            *state = match create() {
                Ok(prepared) if self.stopped() => {
                    prepared.close()?;
                    State::Failed(VfsError::cancelled())
                }
                Ok(prepared) => State::Ready(prepared),
                Err(error) => State::Failed(error),
            };
        }
        check(&|| self.stopped())?;
        match &*state {
            State::Ready(prepared) => Ok(prepared.path.clone()),
            State::Failed(error) => Err(error.clone()),
            _ => Err(VfsError::cancelled()),
        }
    }

    /// Cancels first, then waits for preparation and removes its private
    /// directory. Call only after the document decoder has closed its file.
    pub fn close(&self) -> VfsResult<()> {
        self.cancel();
        let mut state = self.state.lock();
        if let State::Ready(prepared) = std::mem::replace(&mut *state, State::Closed) {
            prepared.close()?;
        }
        Ok(())
    }
}

fn check(stop: Stop) -> VfsResult<()> {
    if stop() {
        Err(VfsError::cancelled())
    } else {
        Ok(())
    }
}

fn stage(
    name: &str,
    stop: Stop,
    write: impl FnOnce(&mut File, &Path) -> VfsResult<()>,
) -> VfsResult<Prepared> {
    check(stop)?;
    let directory = tempfile::Builder::new().prefix("ferryx-preview-").tempdir().at(&std::env::temp_dir())?;
    // Keep the extension for decoders, but never interpret a remote name
    // as a path (backslashes are separators on Windows).
    let name = name.rsplit(['/', '\\']).next().and_then(|n| Path::new(n).file_name());
    let path = directory.path().join(name.unwrap_or_else(|| std::ffi::OsStr::new("preview")));
    let prepared = Prepared { path, directory: Some(directory) };
    let outcome = (|| {
        let mut file = File::create_new(&prepared.path).at(&prepared.path)?;
        write(&mut file, &prepared.path)?;
        check(stop)?;
        file.flush().at(&prepared.path)
    })();
    match outcome {
        Ok(()) => Ok(prepared),
        Err(mut error) => {
            if let Err(cleanup) = prepared.close() {
                error.message.push_str(&format!("; temporary preview cleanup failed: {cleanup}"));
            }
            Err(error)
        }
    }
}

fn copy_remote(reader: &mut dyn RemoteRead, out: &mut dyn Write, path: &Path, stop: Stop) -> VfsResult<()> {
    let mut buffer = [0u8; COPY_BUFFER];
    loop {
        check(stop)?;
        let read = reader.read(&mut buffer, stop)?;
        check(stop)?;
        if read == 0 {
            return Ok(());
        }
        out.write_all(&buffer[..read]).at(path)?;
    }
}

#[cfg(test)]
mod tests;
