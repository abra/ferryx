//! A server's items as panel rows.

use std::path::PathBuf;

use ferryx_core::entry::{extension_of, Entry, EntryKind};

/// What a protocol knows of one item.
#[derive(Clone, Debug, Default)]
pub struct RemoteMeta {
    pub kind: Option<EntryKind>,
    /// A symbolic link that leads to a folder.
    pub link_to_dir: bool,
    pub symlink_target: Option<String>,
    pub size: Option<u64>,
    pub modified_ms: Option<i64>,
    pub created_ms: Option<i64>,
    pub accessed_ms: Option<i64>,
    /// Permission bits (and the type's, when the server sends them).
    pub mode: Option<u32>,
    pub uid: Option<u32>,
    pub gid: Option<u32>,
    pub owner: String,
    pub group: String,
}

/// The type bits of a mode.
const S_IFMT: u32 = 0o170000;
const S_IFDIR: u32 = 0o040000;
const S_IFREG: u32 = 0o100000;
const S_IFLNK: u32 = 0o120000;

/// The row of `name` at `path` on a server.
pub fn entry(name: &str, path: String, meta: RemoteMeta) -> Entry {
    let kind = meta.kind.unwrap_or(EntryKind::File);
    let type_bits = match kind {
        EntryKind::Directory => S_IFDIR,
        EntryKind::Symlink => S_IFLNK,
        EntryKind::File => S_IFREG,
        EntryKind::Other => 0,
    };
    let mode = match meta.mode {
        Some(mode) if mode & S_IFMT != 0 => mode,
        Some(mode) => mode | type_bits,
        None if kind == EntryKind::Directory => type_bits | 0o755,
        None => type_bits | 0o644,
    };
    let is_dir = kind == EntryKind::Directory || (kind == EntryKind::Symlink && meta.link_to_dir);
    Entry {
        name: name.to_string(),
        path: PathBuf::from(path),
        kind,
        is_dir,
        is_parent: false,
        symlink_target: meta.symlink_target,
        size: if kind == EntryKind::Directory { None } else { meta.size },
        modified_ms: meta.modified_ms,
        created_ms: meta.created_ms,
        accessed_ms: meta.accessed_ms,
        added_ms: None,
        mode,
        uid: meta.uid.unwrap_or(0),
        gid: meta.gid.unwrap_or(0),
        owner: meta.owner,
        group: meta.group,
        flags: 0,
        is_hidden: name.starts_with('.'),
        extension: extension_of(name).to_string(),
        tags: Vec::new(),
    }
}

/// The kind a mode's type bits say.
pub fn kind_of_mode(mode: u32) -> Option<EntryKind> {
    match mode & S_IFMT {
        0 => None,
        S_IFDIR => Some(EntryKind::Directory),
        S_IFREG => Some(EntryKind::File),
        S_IFLNK => Some(EntryKind::Symlink),
        _ => Some(EntryKind::Other),
    }
}

/// `drwxr-xr-x` (or `-rw-r--r--`…) as permission bits; `None` when the
/// text is not one.
pub fn mode_of_text(text: &str) -> Option<u32> {
    let bytes = text.as_bytes();
    if bytes.len() < 10 {
        return None;
    }
    let mut mode = 0u32;
    for (i, bit) in (0..9).rev().enumerate() {
        match bytes[1 + i] {
            b'-' => {}
            b'r' | b'w' | b'x' => mode |= 1 << bit,
            b's' | b't' => mode |= 1 << bit,
            b'S' | b'T' => {}
            _ => return None,
        }
    }
    let type_bits = match bytes[0] {
        b'd' => S_IFDIR,
        b'l' => S_IFLNK,
        b'-' => S_IFREG,
        b'c' | b'b' | b'p' | b's' => 0,
        _ => return None,
    };
    Some(mode | type_bits)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rows_from_what_a_server_says() {
        let e = entry(
            ".bashrc",
            "/home/me/.bashrc".into(),
            RemoteMeta {
                kind: Some(EntryKind::File),
                size: Some(12),
                mode: Some(0o644),
                ..Default::default()
            },
        );
        assert!(e.is_hidden);
        assert_eq!(e.mode, 0o100644);
        assert_eq!(e.extension, "");
        let link = entry(
            "www",
            "/www".into(),
            RemoteMeta { kind: Some(EntryKind::Symlink), link_to_dir: true, ..Default::default() },
        );
        assert!(link.is_dir);
        let dir = entry(
            "a.d",
            "/a.d".into(),
            RemoteMeta { kind: Some(EntryKind::Directory), ..Default::default() },
        );
        assert_eq!((dir.extension.as_str(), dir.size, dir.mode), ("d", None, 0o040755));
        assert_eq!(mode_of_text("drwxr-x---"), Some(0o040750));
        assert_eq!(mode_of_text("-rwsr-xr-x"), Some(0o100755));
        assert_eq!(mode_of_text("lrwxrwxrwx"), Some(0o120777));
        assert_eq!(mode_of_text("total 4"), None);
        assert_eq!(kind_of_mode(0o040000), Some(EntryKind::Directory));
    }
}
