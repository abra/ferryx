//! All archive writes are relative to the directory the user chose.
//! Keep an opened parent through conflict questions, writing and cleanup;
//! no archive-controlled path is passed to ambient filesystem writes.

use std::fs::{self, File};
use std::io;
use std::path::{Component, Path, PathBuf};

use cap_std::fs::{Dir, OpenOptions};
use ferryx_vfs::error::VfsError;
use ferryx_vfs::native;

use crate::conflicts::{file_choice, FileChoice};
use crate::runner::OpContext;
use crate::types::*;

pub(super) struct Destination {
    root: Dir,
    path: PathBuf,
}

impl Destination {
    /// Only the user-supplied root is opened with ambient authority.
    pub fn open(ctx: &OpContext, path: &Path) -> io::Result<Self> {
        let top = path.ancestors().take_while(|p| p.symlink_metadata().is_err()).last();
        fs::create_dir_all(path)?;
        if let Some(top) = top {
            ctx.record_created(top);
        }
        Ok(Self {
            root: Dir::open_ambient_dir(path, cap_std::ambient_authority())?,
            path: path.to_path_buf(),
        })
    }

    pub fn path(&self, relative: &Path) -> PathBuf {
        self.path.join(relative)
    }

    pub fn make_folders(&self, ctx: &OpContext, relative: &Path) -> io::Result<()> {
        validate(relative)?;
        if relative.as_os_str().is_empty() {
            return Ok(());
        }
        let top = relative
            .ancestors()
            .take_while(|p| !p.as_os_str().is_empty() && self.root.symlink_metadata(p).is_err())
            .last();
        self.root.create_dir_all(relative)?;
        if let Some(top) = top {
            ctx.record_created(&self.path(top));
        }
        Ok(())
    }

    pub fn target(&self, relative: &Path) -> io::Result<Target> {
        validate(relative)?;
        let name = relative.file_name().ok_or_else(|| io::Error::other("empty archive member path"))?;
        let parent = relative.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
        Ok(Target {
            parent: self.root.open_dir(parent)?,
            name: PathBuf::from(name),
            path: self.path(relative),
        })
    }
}

/// Names are relative on every desktop; on Windows a colon also opens
/// an alternate data stream rather than the file named in the archive.
fn validate(relative: &Path) -> io::Result<()> {
    if relative.components().any(|p| !matches!(p, Component::Normal(_)))
        || (cfg!(windows) && relative.as_os_str().to_string_lossy().contains(':'))
    {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "archive member path is not relative"));
    }
    Ok(())
}

pub(super) struct Target {
    parent: Dir,
    name: PathBuf,
    pub path: PathBuf,
}

impl Target {
    pub fn resolve(
        mut self,
        ctx: &OpContext,
        size: u64,
        modified_ms: Option<i64>,
        policy: ConflictPolicy,
    ) -> Result<Option<Self>, Abort> {
        let existing = match self.parent.symlink_metadata(&self.name) {
            Ok(meta) => meta,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Some(self)),
            Err(e) => {
                ctx.ask_skip(&self.path, &VfsError::io(&e, &self.path))?;
                return Ok(None);
            }
        };
        let choice = file_choice(
            ctx,
            Some(size),
            modified_ms,
            ConflictSide {
                path: self.path.to_string_lossy().into_owned(),
                size: Some(existing.len()),
                modified_ms: existing.modified().ok().and_then(|t| native::system_time_ms(t.into_std())),
                is_dir: existing.is_dir(),
            },
            policy,
        )?;
        let result = match choice {
            FileChoice::Skip => return Ok(None),
            FileChoice::Replace => {
                if existing.is_dir() {
                    self.parent.remove_dir_all(&self.name)
                } else {
                    self.remove_file()
                }
            }
            FileChoice::KeepBoth => self.keep_both(),
        };
        if let Err(e) = result {
            ctx.ask_skip(&self.path, &VfsError::io(&e, &self.path))?;
            return Ok(None);
        }
        if matches!(choice, FileChoice::Replace) {
            ctx.record_overwritten(&self.path);
        }
        Ok(Some(self))
    }

    fn keep_both(&mut self) -> io::Result<()> {
        let name = self.name.to_string_lossy();
        let (stem, ext) = ferryx_core::entry::split_name(&name);
        for n in 2.. {
            let candidate = if ext.is_empty() { format!("{stem} {n}") } else { format!("{stem} {n}.{ext}") };
            match self.parent.symlink_metadata(&candidate) {
                Ok(_) => {}
                Err(e) if e.kind() == io::ErrorKind::NotFound => {
                    self.path.set_file_name(&candidate);
                    self.name = PathBuf::from(candidate);
                    return Ok(());
                }
                Err(e) => return Err(e),
            }
        }
        unreachable!()
    }

    pub fn create(&self) -> io::Result<File> {
        // A file arriving after the question must not be truncated or
        // followed as a link (nor modify another name of a hard link).
        self.parent
            .open_with(&self.name, OpenOptions::new().write(true).create_new(true))
            .map(|f| f.into_std())
    }

    pub fn remove_file(&self) -> io::Result<()> {
        self.parent.remove_file(&self.name)
    }

    pub fn symlink(&self, target: &Path) -> io::Result<()> {
        #[cfg(not(windows))]
        return self.parent.symlink_contents(target, &self.name);
        #[cfg(windows)]
        {
            // Windows needs the link's kind. Only this metadata lookup
            // follows its target; creating the link stays in the handle.
            let resolved = self.path.parent().unwrap_or(Path::new(".")).join(target);
            if resolved.is_dir() {
                self.parent.symlink_dir(target, &self.name)
            } else {
                self.parent.symlink_file(target, &self.name)
            }
        }
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::io::Write;

    fn context() -> OpContext {
        OpContext::detached(&OpRequest {
            kind: OpKind::Extract,
            sources: vec![],
            archive: None,
            destination: None,
            new_name: None,
            options: OpOptions::default(),
        })
    }

    #[test]
    fn a_parent_replaced_after_preparation_does_not_redirect_writes_or_cleanup() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("root");
        let outside = dir.path().join("outside");
        fs::create_dir_all(root.join("parent")).unwrap();
        fs::create_dir(&outside).unwrap();
        let destination = Destination::open(&context(), &root).unwrap();
        let target = destination.target(Path::new("parent/file")).unwrap();
        fs::rename(root.join("parent"), root.join("moved")).unwrap();
        std::os::unix::fs::symlink(&outside, root.join("parent")).unwrap();
        target.create().unwrap().write_all(b"contained").unwrap();
        assert_eq!(fs::read(root.join("moved/file")).unwrap(), b"contained");
        assert!(!outside.join("file").exists());
        fs::write(outside.join("file"), b"untouched").unwrap();
        target.remove_file().unwrap();
        assert_eq!(fs::read(outside.join("file")).unwrap(), b"untouched");
    }

    #[test]
    fn a_link_arriving_after_the_conflict_check_is_never_truncated() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("root");
        let outside = dir.path().join("outside");
        fs::write(&outside, b"untouched").unwrap();
        let destination = Destination::open(&context(), &root).unwrap();
        for hard in [false, true] {
            let name = format!("file-{hard}");
            let target = destination.target(Path::new(&name)).unwrap();
            if hard {
                fs::hard_link(&outside, root.join(&name)).unwrap();
            } else {
                std::os::unix::fs::symlink(&outside, root.join(&name)).unwrap();
            }
            assert!(target.create().is_err());
            assert_eq!(fs::read(&outside).unwrap(), b"untouched");
        }
    }
}
