//! A folder's rows a few hundred at a time (`getattrlistbulk`): each call
//! answers the names and every attribute a row shows, where reading them
//! item by item costs a stat and an attribute read per item.

use std::fs::File;
use std::os::fd::AsRawFd;
use std::path::Path;
use std::ptr;

use ferryx_core::entry::{extension_of, Entry, EntryKind};
use libc::{attribute_set_t, attrlist, attrreference_t, timespec};

use super::{symlink_entry, ListOptions, Names, UF_HIDDEN};
use crate::error::{IoAt, VfsError, VfsErrorKind, VfsResult};

/// Not in `libc`: the item's own error, right after the returned set.
const ATTR_CMN_ERROR: u32 = 0x2000_0000;

const COMMON: u32 = libc::ATTR_CMN_RETURNED_ATTRS
    | libc::ATTR_CMN_NAME
    | ATTR_CMN_ERROR
    | libc::ATTR_CMN_OBJTYPE
    | libc::ATTR_CMN_CRTIME
    | libc::ATTR_CMN_MODTIME
    | libc::ATTR_CMN_ACCTIME
    | libc::ATTR_CMN_OWNERID
    | libc::ATTR_CMN_GRPID
    | libc::ATTR_CMN_ACCESSMASK
    | libc::ATTR_CMN_FLAGS
    | libc::ATTR_CMN_ADDEDTIME;

// `fsobj_type_t` (sys/vnode.h).
const VREG: u32 = 1;
const VDIR: u32 = 2;
const VBLK: u32 = 3;
const VCHR: u32 = 4;
const VLNK: u32 = 5;
const VSOCK: u32 = 6;
const VFIFO: u32 = 7;

const BUFFER: usize = 256 * 1024;

/// Appends the rows of `dir` to `out`. `Ok(false)` when the file system
/// answers no bulk read at all (the caller reads item by item); stops
/// with `Cancelled` once `stop` says so.
pub(super) fn read(
    dir: &Path,
    opts: &ListOptions,
    stop: &dyn Fn() -> bool,
    names: &mut Names,
    out: &mut Vec<Entry>,
) -> VfsResult<bool> {
    let folder = File::open(dir).at(dir)?;
    let mut list: attrlist = unsafe { std::mem::zeroed() };
    list.bitmapcount = libc::ATTR_BIT_MAP_COUNT;
    list.commonattr = COMMON;
    list.fileattr = libc::ATTR_FILE_DATALENGTH;
    let mut buffer = vec![0u8; BUFFER];
    let first = out.len();
    loop {
        if stop() {
            return Err(VfsError::new(VfsErrorKind::Cancelled, Some(dir), "the read was stopped"));
        }
        let count = unsafe {
            libc::getattrlistbulk(
                folder.as_raw_fd(),
                &mut list as *mut attrlist as *mut libc::c_void,
                buffer.as_mut_ptr() as *mut libc::c_void,
                buffer.len(),
                0,
            )
        };
        if count < 0 {
            let error = std::io::Error::last_os_error();
            if out.len() == first && matches!(error.raw_os_error(), Some(libc::ENOTSUP | libc::EINVAL)) {
                return Ok(false);
            }
            return Err(error).at(dir);
        }
        if count == 0 {
            return Ok(true);
        }
        let mut at = 0;
        for _ in 0..count {
            let length = read_at::<u32>(&buffer, at) as usize;
            if length == 0 || at + length > buffer.len() {
                return Err(VfsError::new(VfsErrorKind::Io, Some(dir), "a malformed attribute buffer"));
            }
            if let Some(entry) = parse(&buffer[at..at + length], dir, opts, names) {
                out.push(entry);
            }
            at += length;
        }
    }
}

/// One item of the buffer, or `None` for an item hidden from `opts` or
/// one the file system could not read.
fn parse(item: &[u8], dir: &Path, opts: &ListOptions, names: &mut Names) -> Option<Entry> {
    // The attributes follow in the order of their bits, each only if it
    // was returned; `RETURNED_ATTRS` and `ERROR` lead.
    let returned: attribute_set_t = read_at(item, 4);
    let common = returned.commonattr;
    let mut at = 4 + std::mem::size_of::<attribute_set_t>();
    let mut next = |bit: u32, size: usize| -> Option<usize> {
        (common & bit != 0).then(|| {
            let here = at;
            at += size;
            here
        })
    };
    let error = next(ATTR_CMN_ERROR, 4).map(|p| read_at::<u32>(item, p)).unwrap_or(0);
    let name_at = next(libc::ATTR_CMN_NAME, std::mem::size_of::<attrreference_t>());
    let kind_at = next(libc::ATTR_CMN_OBJTYPE, 4);
    let created_at = next(libc::ATTR_CMN_CRTIME, std::mem::size_of::<timespec>());
    let modified_at = next(libc::ATTR_CMN_MODTIME, std::mem::size_of::<timespec>());
    let accessed_at = next(libc::ATTR_CMN_ACCTIME, std::mem::size_of::<timespec>());
    let uid_at = next(libc::ATTR_CMN_OWNERID, 4);
    let gid_at = next(libc::ATTR_CMN_GRPID, 4);
    let mask_at = next(libc::ATTR_CMN_ACCESSMASK, 4);
    let flags_at = next(libc::ATTR_CMN_FLAGS, 4);
    let added_at = next(libc::ATTR_CMN_ADDEDTIME, std::mem::size_of::<timespec>());
    let length_at = (returned.fileattr & libc::ATTR_FILE_DATALENGTH != 0).then_some(at);
    if error != 0 {
        return None;
    }

    let reference: attrreference_t = read_at(item, name_at?);
    let start = name_at? + usize::try_from(reference.attr_dataoffset).ok()?;
    // The length counts the closing NUL.
    let end = start + (reference.attr_length as usize).checked_sub(1)?;
    let name = String::from_utf8_lossy(item.get(start..end)?).into_owned();
    let flags = flags_at.map(|p| read_at::<u32>(item, p)).unwrap_or(0);
    let is_hidden = name.starts_with('.') || flags & UF_HIDDEN != 0;
    if is_hidden && !opts.show_hidden {
        return None;
    }

    let object = kind_at.map(|p| read_at::<u32>(item, p)).unwrap_or(0);
    let path = dir.join(&name);
    let (kind, is_dir, symlink_target) = match object {
        VDIR => (EntryKind::Directory, true, None),
        VREG => (EntryKind::File, false, None),
        VLNK => symlink_entry(&path),
        _ => (EntryKind::Other, false, None),
    };
    let type_bits = match object {
        VREG => libc::S_IFREG,
        VDIR => libc::S_IFDIR,
        VLNK => libc::S_IFLNK,
        VBLK => libc::S_IFBLK,
        VCHR => libc::S_IFCHR,
        VSOCK => libc::S_IFSOCK,
        VFIFO => libc::S_IFIFO,
        _ => 0,
    } as u32;
    let uid = uid_at.map(|p| read_at::<u32>(item, p)).unwrap_or(0);
    let gid = gid_at.map(|p| read_at::<u32>(item, p)).unwrap_or(0);
    let mask = mask_at.map(|p| read_at::<u32>(item, p)).unwrap_or(0);
    let time = |at: Option<usize>| at.map(|p| millis(read_at::<timespec>(item, p)));
    Some(Entry {
        extension: extension_of(&name).to_string(),
        kind,
        is_dir,
        is_parent: false,
        symlink_target,
        size: if kind == EntryKind::Directory {
            None
        } else {
            Some(length_at.map(|p| read_at::<i64>(item, p).max(0) as u64).unwrap_or(0))
        },
        modified_ms: time(modified_at),
        created_ms: time(created_at),
        accessed_ms: time(accessed_at),
        added_ms: time(added_at).filter(|&ms| ms != 0),
        mode: type_bits | (mask & 0o7777),
        uid,
        gid,
        owner: names.owner(uid),
        group: names.group(gid),
        flags,
        is_hidden,
        tags: Vec::new(),
        name,
        path,
    })
}

/// A value at `at`, which the buffer does not align.
fn read_at<T: Copy>(buffer: &[u8], at: usize) -> T {
    assert!(at + std::mem::size_of::<T>() <= buffer.len(), "attribute past the item's end");
    unsafe { ptr::read_unaligned(buffer.as_ptr().add(at) as *const T) }
}

/// As `system_time_ms` reads the same moment from a stat.
fn millis(time: timespec) -> i64 {
    if time.tv_sec >= 0 {
        time.tv_sec * 1000 + time.tv_nsec / 1_000_000
    } else {
        // Before 1970: whole milliseconds towards the epoch, as a
        // `SystemTime`'s distance from it is cut.
        let nanos = -(time.tv_sec as i128 * 1_000_000_000 + time.tv_nsec as i128);
        -((nanos / 1_000_000) as i64)
    }
}
