//! Identifies a local directory entry independently of its name and contents.

use std::{fs::File, io, path::Path, time::SystemTime};

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileIdentity {
    volume: u64,
    file: [u8; 16],
    // Helps distinguish reused IDs on filesystems that report a creation time.
    created: Option<SystemTime>,
}

impl FileIdentity {
    /// Looks at the entry itself, even when it is a dangling symlink.
    #[cfg(unix)]
    pub fn of(path: &Path) -> io::Result<Self> {
        Ok(Self::from_metadata(&path.symlink_metadata()?))
    }

    #[cfg(unix)]
    pub fn of_file(file: &File) -> io::Result<Self> {
        Ok(Self::from_metadata(&file.metadata()?))
    }

    #[cfg(unix)]
    fn from_metadata(meta: &std::fs::Metadata) -> Self {
        use std::os::unix::fs::MetadataExt;

        Self { volume: meta.dev(), file: u128::from(meta.ino()).to_le_bytes(), created: meta.created().ok() }
    }

    #[cfg(windows)]
    pub fn of(path: &Path) -> io::Result<Self> {
        use std::os::windows::fs::OpenOptionsExt;
        use windows_sys::Win32::Storage::FileSystem::{
            FILE_FLAG_BACKUP_SEMANTICS, FILE_FLAG_OPEN_REPARSE_POINT,
        };

        let file = std::fs::OpenOptions::new()
            .access_mode(0)
            .custom_flags(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT)
            .open(path)?;
        Self::of_file(&file)
    }

    #[cfg(windows)]
    pub fn of_file(file: &File) -> io::Result<Self> {
        use std::os::windows::io::AsRawHandle;
        use windows_sys::Win32::Storage::FileSystem::{
            FileIdInfo, GetFileInformationByHandleEx, FILE_ID_INFO,
        };

        let mut id = FILE_ID_INFO::default();
        // The handle is open and the buffer is a writable FILE_ID_INFO of the given size.
        let ok = unsafe {
            GetFileInformationByHandleEx(
                file.as_raw_handle(),
                FileIdInfo,
                (&mut id as *mut FILE_ID_INFO).cast(),
                std::mem::size_of::<FILE_ID_INFO>() as u32,
            )
        };
        if ok == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self {
            volume: id.VolumeSerialNumber,
            file: id.FileId.Identifier,
            created: file.metadata()?.created().ok(),
        })
    }

    #[cfg(not(any(unix, windows)))]
    pub fn of(_path: &Path) -> io::Result<Self> {
        Err(io::Error::from(io::ErrorKind::Unsupported))
    }

    #[cfg(not(any(unix, windows)))]
    pub fn of_file(_file: &File) -> io::Result<Self> {
        Err(io::Error::from(io::ErrorKind::Unsupported))
    }

    /// The opaque value carried through the UI back to a delayed operation.
    pub fn token(self) -> String {
        format!("{:x}:{:x}:{:?}", self.volume, u128::from_le_bytes(self.file), self.created)
    }

    pub(crate) fn same_entry(self, other: Self) -> bool {
        self.volume == other.volume && self.file == other.file
    }
}
