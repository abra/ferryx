//! Finder tags (macOS): read with every listed item, written for a
//! command.
//!
//! The tags are the extended attribute
//! `com.apple.metadata:_kMDItemUserTags`, a binary property list holding
//! an array of strings `Name\nColour` (the colour in Finder's numbering,
//! left out when none). Finder also keeps the colour of an item's last
//! coloured tag in its legacy Finder info (`com.apple.FinderInfo`, the
//! label bits of the Finder flags); a write keeps that in step, so the
//! Finder of older systems and other tools agree. The attributes are read
//! and written on the item itself, never through a symbolic link.
//!
//! Reading costs one `getxattr` per item (a second one only for a very
//! long list of tags) — about 14 µs on APFS even for an item without
//! tags, more than the rest of its row costs (measured on 10 000 files:
//! 0.06–0.1 s to list, 0.14–0.16 s more for the tags; see
//! [`tests::tag_reading_cost`]). So a listing does not read them: the
//! panel asks for a listing's tags once it shows (`read_listing_tags`)
//! and the dots follow a moment later; one item (`native::stat`) reads
//! its own.

use std::path::Path;

use ferryx_core::entry::Tag;

use crate::error::{VfsError, VfsResult};

/// Where Finder keeps the tags.
pub const TAGS_ATTRIBUTE: &str = "com.apple.metadata:_kMDItemUserTags";

/// Where Finder keeps an item's legacy colour label.
pub const FINDER_INFO_ATTRIBUTE: &str = "com.apple.FinderInfo";

/// Whether this desktop has Finder tags.
pub fn supported() -> bool {
    cfg!(target_os = "macos")
}

/// The tags of the item at `path`; none where tags are not kept, or when
/// they cannot be read.
pub fn read(path: &Path) -> Vec<Tag> {
    match sys::get(path, TAGS_ATTRIBUTE) {
        Ok(Some(data)) => decode(&data),
        _ => Vec::new(),
    }
}

/// Adds `add` (a tag already there takes the colour given) and takes off
/// the tags named in `remove` (case aside), keeping the rest in their
/// order; answers the item's tags after.
pub fn apply(path: &Path, add: &[Tag], remove: &[String]) -> VfsResult<Vec<Tag>> {
    if !supported() {
        return Err(VfsError::unsupported("Finder tags are kept on macOS only"));
    }
    let before = match sys::get(path, TAGS_ATTRIBUTE) {
        Ok(Some(data)) => decode(&data),
        Ok(None) => Vec::new(),
        Err(e) => return Err(VfsError::io(&e, path)),
    };
    let after = edited(&before, add, remove);
    if after != before {
        write(path, &after)?;
    }
    Ok(after)
}

/// The tags `before` with `add` and without `remove`.
pub fn edited(before: &[Tag], add: &[Tag], remove: &[String]) -> Vec<Tag> {
    let same = |a: &str, b: &str| a.to_lowercase() == b.to_lowercase();
    let mut tags: Vec<Tag> =
        before.iter().filter(|t| !remove.iter().any(|r| same(r, &t.name))).cloned().collect();
    for tag in add {
        match tags.iter_mut().find(|t| same(&t.name, &tag.name)) {
            Some(existing) => existing.color = tag.color,
            None => tags.push(tag.clone()),
        }
    }
    tags
}

/// Writes `tags` as the item's tags (none takes the attribute off) and
/// keeps the Finder info's colour label in step.
pub fn write(path: &Path, tags: &[Tag]) -> VfsResult<()> {
    let result = if tags.is_empty() {
        sys::remove(path, TAGS_ATTRIBUTE)
    } else {
        sys::set(path, TAGS_ATTRIBUTE, &encode(tags))
    };
    result.map_err(|e| VfsError::io(&e, path))?;
    let label = tags.iter().rev().map(|t| t.color).find(|&c| c > 0).unwrap_or(0);
    // The legacy label is a courtesy: the tags are written already.
    let _ = set_finder_label(path, label);
    Ok(())
}

/// The label bits of the Finder flags (bytes 8 and 9 of the Finder info,
/// big-endian), as the colour number shifted left by one.
const LABEL_MASK: u16 = 0x000E;

fn set_finder_label(path: &Path, color: u8) -> std::io::Result<()> {
    let existing = sys::get(path, FINDER_INFO_ATTRIBUTE)?;
    let mut info = match existing {
        Some(info) if info.len() == 32 => info,
        // Nothing to clear where there is no Finder info.
        _ if color == 0 => return Ok(()),
        _ => vec![0u8; 32],
    };
    let flags = u16::from_be_bytes([info[8], info[9]]);
    let flags = (flags & !LABEL_MASK) | ((color as u16) << 1 & LABEL_MASK);
    info[8..10].copy_from_slice(&flags.to_be_bytes());
    if info.iter().all(|&b| b == 0) {
        sys::remove(path, FINDER_INFO_ATTRIBUTE)
    } else {
        sys::set(path, FINDER_INFO_ATTRIBUTE, &info)
    }
}

/// The tags in the property list Finder writes.
pub fn decode(data: &[u8]) -> Vec<Tag> {
    let Ok(value) = plist::Value::from_reader(std::io::Cursor::new(data)) else { return Vec::new() };
    let Some(items) = value.as_array() else { return Vec::new() };
    items
        .iter()
        .filter_map(|item| item.as_string())
        .filter(|text| !text.is_empty())
        .map(|text| match text.rsplit_once('\n') {
            Some((name, color)) => Tag::new(name, color.trim().parse::<u8>().unwrap_or(0)),
            None => Tag::new(text, 0),
        })
        .collect()
}

/// The tags as the binary property list Finder reads.
pub fn encode(tags: &[Tag]) -> Vec<u8> {
    let items = tags
        .iter()
        .map(|t| {
            plist::Value::String(if t.color > 0 {
                format!("{}\n{}", t.name, t.color)
            } else {
                t.name.clone()
            })
        })
        .collect();
    let mut out = Vec::new();
    plist::Value::Array(items).to_writer_binary(&mut out).expect("a property list of strings encodes");
    out
}

#[cfg(target_os = "macos")]
mod sys {
    use std::ffi::CString;
    use std::io;
    use std::os::unix::ffi::OsStrExt;
    use std::path::Path;

    fn c_strings(path: &Path, name: &str) -> io::Result<(CString, CString)> {
        Ok((CString::new(path.as_os_str().as_bytes())?, CString::new(name)?))
    }

    /// The attribute's value; `None` when the item has none.
    pub fn get(path: &Path, name: &str) -> io::Result<Option<Vec<u8>>> {
        let (c_path, c_name) = c_strings(path, name)?;
        // Most tag lists fit; a longer one is read again at its size.
        let mut buffer = vec![0u8; 512];
        loop {
            let read = unsafe {
                libc::getxattr(
                    c_path.as_ptr(),
                    c_name.as_ptr(),
                    buffer.as_mut_ptr() as *mut libc::c_void,
                    buffer.len(),
                    0,
                    libc::XATTR_NOFOLLOW,
                )
            };
            if read >= 0 {
                buffer.truncate(read as usize);
                return Ok(Some(buffer));
            }
            let error = io::Error::last_os_error();
            match error.raw_os_error() {
                Some(libc::ENOATTR) => return Ok(None),
                Some(libc::ERANGE) => {
                    let size = unsafe {
                        libc::getxattr(
                            c_path.as_ptr(),
                            c_name.as_ptr(),
                            std::ptr::null_mut(),
                            0,
                            0,
                            libc::XATTR_NOFOLLOW,
                        )
                    };
                    if size < 0 {
                        return Err(io::Error::last_os_error());
                    }
                    buffer = vec![0u8; size as usize];
                }
                _ => return Err(error),
            }
        }
    }

    pub fn set(path: &Path, name: &str, value: &[u8]) -> io::Result<()> {
        let (c_path, c_name) = c_strings(path, name)?;
        let rc = unsafe {
            libc::setxattr(
                c_path.as_ptr(),
                c_name.as_ptr(),
                value.as_ptr() as *const libc::c_void,
                value.len(),
                0,
                libc::XATTR_NOFOLLOW,
            )
        };
        if rc == 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }

    pub fn remove(path: &Path, name: &str) -> io::Result<()> {
        let (c_path, c_name) = c_strings(path, name)?;
        let rc = unsafe { libc::removexattr(c_path.as_ptr(), c_name.as_ptr(), libc::XATTR_NOFOLLOW) };
        if rc == 0 {
            return Ok(());
        }
        let error = io::Error::last_os_error();
        if error.raw_os_error() == Some(libc::ENOATTR) {
            Ok(())
        } else {
            Err(error)
        }
    }
}

#[cfg(not(target_os = "macos"))]
mod sys {
    use std::io;
    use std::path::Path;

    pub fn get(_path: &Path, _name: &str) -> io::Result<Option<Vec<u8>>> {
        Ok(None)
    }

    pub fn set(_path: &Path, _name: &str, _value: &[u8]) -> io::Result<()> {
        Err(io::Error::from(io::ErrorKind::Unsupported))
    }

    pub fn remove(_path: &Path, _name: &str) -> io::Result<()> {
        Err(io::Error::from(io::ErrorKind::Unsupported))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn property_lists_round_trip() {
        let tags = vec![Tag::new("Red", 6), Tag::new("work", 0), Tag::new("Блок", 4)];
        assert_eq!(decode(&encode(&tags)), tags);
        assert_eq!(decode(b"not a plist"), Vec::<Tag>::new());
    }

    #[test]
    fn edits_keep_the_order_and_ignore_case() {
        let before = vec![Tag::new("Red", 6), Tag::new("work", 0)];
        assert_eq!(
            edited(&before, &[Tag::new("Blue", 4)], &["RED".to_string()]),
            [Tag::new("work", 0), Tag::new("Blue", 4)]
        );
        assert_eq!(edited(&before, &[Tag::new("WORK", 2)], &[]), [Tag::new("Red", 6), Tag::new("work", 2)]);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn writes_tags_and_the_finder_label() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("f.txt");
        std::fs::write(&file, b"x").unwrap();
        assert!(read(&file).is_empty());
        let after = apply(&file, &[Tag::new("Green", 2), Tag::new("Red", 6)], &[]).unwrap();
        assert_eq!(read(&file), after);
        let info = sys::get(&file, FINDER_INFO_ATTRIBUTE).unwrap().unwrap();
        assert_eq!(u16::from_be_bytes([info[8], info[9]]) & LABEL_MASK, 6 << 1);
        // Taking every tag off clears both.
        apply(&file, &[], &["green".into(), "red".into()]).unwrap();
        assert!(read(&file).is_empty());
        assert_eq!(sys::get(&file, TAGS_ATTRIBUTE).unwrap(), None);
        assert_eq!(sys::get(&file, FINDER_INFO_ATTRIBUTE).unwrap(), None);
        // The listing reads them.
        apply(&file, &[Tag::new("Blue", 4)], &[]).unwrap();
        assert_eq!(crate::native::stat(&file).unwrap().tags, [Tag::new("Blue", 4)]);
    }

    /// Times reading tags against listing: `cargo test --release -p
    /// ferryx_vfs tag_reading_cost -- --ignored --nocapture`.
    #[cfg(target_os = "macos")]
    #[test]
    #[ignore]
    fn tag_reading_cost() {
        use std::time::Instant;
        let dir = tempfile::tempdir().unwrap();
        for i in 0..10_000 {
            std::fs::write(dir.path().join(format!("f{i}")), b"").unwrap();
        }
        for i in (0..10_000).step_by(10) {
            write(&dir.path().join(format!("f{i}")), &[Tag::new("Red", 6)]).unwrap();
        }
        let options = crate::native::ListOptions { show_hidden: true, show_parent: false };
        // Warm the cache, then time.
        crate::native::list_dir(dir.path(), &options).unwrap();
        let start = Instant::now();
        let rows = crate::native::list_dir(dir.path(), &options).unwrap();
        let listed = start.elapsed();
        let start = Instant::now();
        let tagged = rows.iter().filter(|e| !read(&e.path).is_empty()).count();
        let tags_alone = start.elapsed();
        println!("10 000 files listed in {listed:?}; their tags take {tags_alone:?} more ({tagged} tagged)");
    }
}
