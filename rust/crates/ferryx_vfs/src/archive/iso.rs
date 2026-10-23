//! ISO 9660 images (ECMA-119): the member list from the directory
//! records, with the long names of Rock Ridge (`NM`) or, without them, of
//! Joliet (UCS-2 names in a supplementary volume descriptor); a member's
//! bytes are its extents, read straight from the image.

use std::collections::HashSet;
use std::fs::File;
use std::io::{self, BufReader, Read, Seek, SeekFrom};
use std::path::Path;

use super::formats::Job;
use super::{Backing, ExtractError, Listed, Member, MemberSink, SinkWriter};
use crate::error::{IoAt, VfsError, VfsErrorKind, VfsResult};

const SECTOR: u64 = 2048;

/// No image is this deep; a loop in the records stops here.
const MAX_DEPTH: usize = 64;

/// A directory record's fields that matter here.
#[derive(Clone)]
struct Record {
    extent: u64,
    length: u64,
    is_dir: bool,
    /// More extents of the same file follow (a file of 4 GiB or more).
    multi_extent: bool,
    modified_ms: Option<i64>,
    /// The name as recorded (ISO or Joliet), `None` for `.` and `..`.
    name: Option<String>,
    /// The Rock Ridge name and mode, when the record has them.
    rr_name: Option<String>,
    rr_mode: Option<u32>,
    rr_link: Option<String>,
}

/// The name family a tree is read with.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Names {
    Iso,
    Joliet,
}

pub(crate) fn list(archive: &Path) -> VfsResult<Listed> {
    let mut file = BufReader::new(File::open(archive).at(archive)?);
    let mut primary = None;
    let mut joliet = None;
    for sector in 16..16 + 64 {
        let mut descriptor = [0u8; 2048];
        file.seek(SeekFrom::Start(sector * SECTOR)).at(archive)?;
        if file.read_exact(&mut descriptor).is_err() || &descriptor[1..6] != b"CD001" {
            break;
        }
        match descriptor[0] {
            1 if primary.is_none() => primary = Some(root_of(&descriptor)),
            2 if is_joliet(&descriptor) && joliet.is_none() => joliet = Some(root_of(&descriptor)),
            255 => break,
            _ => {}
        }
    }
    let primary = primary.ok_or_else(|| bad_image(archive))?;
    // Rock Ridge names win: they keep case, length and modes. Without
    // them Joliet's long names do; plain ISO names are the last resort.
    let rock_ridge = has_rock_ridge(&mut file, &primary).unwrap_or(false);
    let (root, names) = match (joliet, rock_ridge) {
        (Some(joliet), false) => (joliet, Names::Joliet),
        _ => (primary, Names::Iso),
    };
    let mut tree =
        Tree { file: &mut file, names, seen: HashSet::new(), members: Vec::new(), extents: Vec::new() };
    tree.walk(root, "", 0).at(archive)?;
    let Tree { members, extents, .. } = tree;
    Ok(Listed { members, headers_encrypted: false, backing: Backing::Iso(extents) })
}

fn bad_image(archive: &Path) -> VfsError {
    VfsError::new(
        VfsErrorKind::Unsupported,
        Some(archive),
        format!("{} is not an ISO 9660 image", archive.display()),
    )
}

/// A supplementary descriptor is Joliet's when its escape sequences name
/// UCS-2 level 1, 2 or 3.
fn is_joliet(descriptor: &[u8]) -> bool {
    let escapes = &descriptor[88..120];
    escapes.windows(3).any(|w| w == b"%/@" || w == b"%/C" || w == b"%/E")
}

/// The root directory's record of a volume descriptor.
fn root_of(descriptor: &[u8]) -> (u64, u64) {
    let record = &descriptor[156..190];
    (le32(&record[2..6]) as u64, le32(&record[10..14]) as u64)
}

fn le32(bytes: &[u8]) -> u32 {
    u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
}

/// Whether the root's `.` record carries the SUSP `SP` mark or a Rock
/// Ridge entry.
fn has_rock_ridge<R: Read + Seek>(file: &mut R, root: &(u64, u64)) -> io::Result<bool> {
    let mut sector = [0u8; 2048];
    file.seek(SeekFrom::Start(root.0 * SECTOR))?;
    file.read_exact(&mut sector)?;
    let length = sector[0] as usize;
    if length < 34 {
        return Ok(false);
    }
    let name_len = sector[32] as usize;
    let mut at = 33 + name_len;
    if name_len % 2 == 0 {
        at += 1;
    }
    let system_use = &sector[at.min(length)..length];
    // An `SP` and an `ER` naming RRIP only announce it (hdiutil writes them
    // with no Rock Ridge entry anywhere): the root must carry one itself.
    let rock_ridge = susp_signatures(system_use).any(|signature| matches!(&signature, b"PX" | b"NM" | b"RR"));
    Ok(rock_ridge)
}

/// The signatures of the SUSP entries in a record's system use area, each
/// entry `signature, length, version, data`; a length that cannot be one
/// ends the walk.
fn susp_signatures(system_use: &[u8]) -> impl Iterator<Item = [u8; 2]> + '_ {
    let mut at = 0;
    std::iter::from_fn(move || {
        let entry = system_use.get(at..at + 4)?;
        let length = entry[2] as usize;
        if length < 4 {
            return None;
        }
        at += length;
        Some([entry[0], entry[1]])
    })
}

/// A file whose extents are being gathered (one record each).
struct PendingFile {
    path: String,
    extents: Vec<(u64, u64)>,
    first: Record,
}

/// The member list as a tree of directories is read into it.
struct Tree<'a, R> {
    file: &'a mut R,
    names: Names,
    /// Directories read already, by extent: a loop in the records stops.
    seen: HashSet<u64>,
    members: Vec<Member>,
    extents: Vec<Vec<(u64, u64)>>,
}

impl<R: Read + Seek> Tree<'_, R> {
    fn walk(&mut self, dir: (u64, u64), prefix: &str, depth: usize) -> io::Result<()> {
        if depth > MAX_DEPTH || !self.seen.insert(dir.0) {
            return Ok(());
        }
        let records = read_dir(self.file, &dir, self.names)?;
        let mut pending: Option<PendingFile> = None;
        for record in records {
            let Some(name) = record.rr_name.clone().or_else(|| record.name.clone()) else { continue };
            if name.is_empty() || name == "." || name == ".." || name.contains('/') {
                continue;
            }
            let path = if prefix.is_empty() { name } else { format!("{prefix}/{name}") };
            if record.is_dir {
                self.members.push(Member {
                    path: path.clone(),
                    is_dir: true,
                    is_symlink: false,
                    size: 0,
                    modified_ms: record.modified_ms,
                    mode: record.rr_mode.unwrap_or(0o40755),
                    encrypted: false,
                    native: None,
                    link: None,
                });
                self.walk((record.extent, record.length), &path, depth + 1)?;
                continue;
            }
            // The extents of a file of several records go together.
            let mut file = match pending.take() {
                Some(file) if file.path == path => file,
                Some(other) => {
                    self.push_file(other);
                    PendingFile { path, extents: Vec::new(), first: record.clone() }
                }
                None => PendingFile { path, extents: Vec::new(), first: record.clone() },
            };
            file.extents.push((record.extent * SECTOR, record.length));
            if record.multi_extent {
                pending = Some(file);
            } else {
                self.push_file(file);
            }
        }
        if let Some(last) = pending {
            self.push_file(last);
        }
        Ok(())
    }

    fn push_file(&mut self, file: PendingFile) {
        let size = file.extents.iter().map(|(_, len)| len).sum();
        let mode = file.first.rr_mode.unwrap_or(0o100644);
        self.members.push(Member {
            path: file.path,
            is_dir: false,
            is_symlink: mode & 0o170000 == 0o120000,
            size,
            modified_ms: file.first.modified_ms,
            mode,
            encrypted: false,
            native: Some(self.extents.len() as u64),
            link: file.first.rr_link,
        });
        self.extents.push(file.extents);
    }
}

/// The records of one directory, read sector by sector (a record never
/// crosses a sector's end; a zero length means the rest is padding).
fn read_dir<R: Read + Seek>(file: &mut R, dir: &(u64, u64), names: Names) -> io::Result<Vec<Record>> {
    let (extent, length) = *dir;
    // A directory is never this large; a broken length is not believed.
    let length = length.min(64 * 1024 * 1024);
    let mut data = vec![0u8; length as usize];
    file.seek(SeekFrom::Start(extent * SECTOR))?;
    file.read_exact(&mut data)?;
    let mut records = Vec::new();
    let mut at = 0usize;
    while at < data.len() {
        let len = data[at] as usize;
        if len == 0 {
            at = (at / SECTOR as usize + 1) * SECTOR as usize;
            continue;
        }
        if len < 34 || at + len > data.len() {
            break;
        }
        records.push(parse_record(&data[at..at + len], names));
        at += len;
    }
    Ok(records)
}

fn parse_record(record: &[u8], names: Names) -> Record {
    let flags = record[25];
    let name_len = record[32] as usize;
    let raw = &record[33..(33 + name_len).min(record.len())];
    let name = match raw {
        [0] | [1] => None,
        _ => Some(match names {
            Names::Joliet => joliet_name(raw),
            Names::Iso => iso_name(raw),
        }),
    };
    let mut system_at = 33 + name_len;
    if name_len % 2 == 0 {
        system_at += 1;
    }
    let (rr_name, rr_mode, rr_link) = if names == Names::Iso && system_at < record.len() {
        rock_ridge(&record[system_at..])
    } else {
        (None, None, None)
    };
    Record {
        extent: le32(&record[2..6]) as u64,
        length: le32(&record[10..14]) as u64,
        is_dir: flags & 0x02 != 0,
        multi_extent: flags & 0x80 != 0,
        modified_ms: record_time(&record[18..25]),
        name,
        rr_name,
        rr_mode,
        rr_link,
    }
}

/// `NAME.EXT;1` → `NAME.EXT`; `NAME.;1` → `NAME`.
fn iso_name(raw: &[u8]) -> String {
    let text = String::from_utf8_lossy(raw);
    let text = match text.rfind(';') {
        Some(at) => &text[..at],
        None => &text,
    };
    text.trim_end_matches('.').to_string()
}

fn joliet_name(raw: &[u8]) -> String {
    let units: Vec<u16> = raw.chunks_exact(2).map(|c| u16::from_be_bytes([c[0], c[1]])).collect();
    let text = String::from_utf16_lossy(&units);
    match text.rfind(';') {
        Some(at) => text[..at].to_string(),
        None => text,
    }
}

/// The Rock Ridge name (`NM`, joined across continued entries), mode
/// (`PX`) and link target (`SL`) of a record's system use area.
fn rock_ridge(area: &[u8]) -> (Option<String>, Option<u32>, Option<String>) {
    let mut name: Option<Vec<u8>> = None;
    let mut mode = None;
    let mut link: Option<Vec<u8>> = None;
    let mut at = 0;
    while at + 4 <= area.len() {
        let len = area[at + 2] as usize;
        if len < 4 || at + len > area.len() {
            break;
        }
        let entry = &area[at..at + len];
        match &entry[0..2] {
            b"NM" if len >= 5 => {
                let flags = entry[4];
                // `.` and `..` flags carry no name.
                if flags & 0x06 == 0 {
                    name.get_or_insert_with(Vec::new).extend_from_slice(&entry[5..]);
                }
            }
            b"PX" if len >= 12 => mode = Some(le32(&entry[4..8])),
            b"SL" if len >= 5 => {
                let target = link.get_or_insert_with(Vec::new);
                let mut c = 5;
                while c + 2 <= entry.len() {
                    let flags = entry[c];
                    let clen = entry[c + 1] as usize;
                    let content = &entry[(c + 2).min(entry.len())..(c + 2 + clen).min(entry.len())];
                    if !target.is_empty() && !target.ends_with(b"/") {
                        target.push(b'/');
                    }
                    match flags & 0x0E {
                        0x02 => target.extend_from_slice(b"."),
                        0x04 => target.extend_from_slice(b".."),
                        0x08 => target.push(b'/'),
                        _ => target.extend_from_slice(content),
                    }
                    c += 2 + clen;
                }
            }
            b"ST" => break,
            _ => {}
        }
        at += len;
    }
    (
        name.map(|n| String::from_utf8_lossy(&n).into_owned()),
        mode,
        link.map(|l| String::from_utf8_lossy(&l).into_owned()),
    )
}

/// A directory record's seven-byte time: years since 1900, month, day,
/// hour, minute, second, and the zone in quarters of an hour.
fn record_time(bytes: &[u8]) -> Option<i64> {
    use chrono::{FixedOffset, TimeZone};
    let year = 1900 + bytes[0] as i32;
    let offset = FixedOffset::east_opt((bytes[6] as i8) as i32 * 15 * 60)?;
    offset
        .with_ymd_and_hms(
            year,
            bytes[1] as u32,
            bytes[2] as u32,
            bytes[3] as u32,
            bytes[4] as u32,
            bytes[5] as u32,
        )
        .single()
        .map(|t| t.timestamp_millis())
}

pub(crate) fn extract(job: &Job, sink: &mut dyn MemberSink) -> Result<(), ExtractError> {
    let archive = &job.index.archive;
    let Backing::Iso(extents) = &job.index.backing else {
        return Err(ExtractError::Failed(VfsError::unsupported("not an ISO image")));
    };
    let mut file = File::open(archive).at(archive)?;
    for &at in job.picked {
        let member = &job.index.members[at];
        let Some(parts) = member.native.and_then(|n| extents.get(n as usize)) else { continue };
        if !sink.begin(member)? {
            continue;
        }
        let mut outcome = Ok(0u64);
        for &(offset, length) in parts {
            let read = file
                .seek(SeekFrom::Start(offset))
                .and_then(|_| super::pump(&mut (&mut file).take(length), &mut SinkWriter(sink)));
            match read {
                Ok(n) => outcome = outcome.map(|total| total + n),
                Err(e) => {
                    outcome = Err(VfsError::io(&e, archive));
                    break;
                }
            }
        }
        sink.end(member, outcome)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A root `.` record carrying `system_use` after its one-byte name.
    fn root_with(system_use: &[u8]) -> io::Cursor<Vec<u8>> {
        let mut sector = vec![0u8; 2048];
        let length = 34 + system_use.len();
        sector[0] = length as u8;
        sector[32] = 1;
        sector[34..34 + system_use.len()].copy_from_slice(system_use);
        io::Cursor::new(sector)
    }

    fn entry(signature: &[u8; 2], data: &[u8]) -> Vec<u8> {
        let mut out = vec![signature[0], signature[1], (4 + data.len()) as u8, 1];
        out.extend_from_slice(data);
        out
    }

    #[test]
    fn rock_ridge_is_its_entries_not_its_announcement() {
        // hdiutil's way: SP and an ER naming RRIP, and no entry of it.
        let announced =
            [entry(b"SP", &[0xBE, 0xEF, 0]), entry(b"ER", b"\x0a\x00\x00\x01IEEE_P1282")].concat();
        assert!(!has_rock_ridge(&mut root_with(&announced), &(0, 2048)).unwrap());
        // mkisofs's: the root's own attributes as a PX entry.
        let real = [entry(b"SP", &[0xBE, 0xEF, 0]), entry(b"PX", &[0; 32])].concat();
        assert!(has_rock_ridge(&mut root_with(&real), &(0, 2048)).unwrap());
        // A length that cannot be an entry's ends the walk, never loops.
        assert!(!has_rock_ridge(&mut root_with(&[b'P', b'X', 0, 1]), &(0, 2048)).unwrap());
    }
}
