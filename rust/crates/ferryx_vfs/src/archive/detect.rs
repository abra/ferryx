//! What an archive is, by its first bytes and then by its name.

use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom};
use std::path::Path;

use super::formats::decoder;
use super::{format_of, ArchiveFormat, Compression};
use crate::error::{IoAt, VfsResult};

/// Where an ISO 9660 image says so: the first volume descriptor's
/// standard identifier, at sector 16.
const ISO_MAGIC_AT: u64 = 16 * 2048 + 1;

/// The format of the file at `path`: its magic bytes first, so a `.zip`
/// that is a 7z opens as one and ⌘↓ opens an archive of any name; its name
/// when the bytes say nothing (an old tar without the `ustar` mark, a
/// self-extracting zip). A compressed stream is a tar when its first
/// block reads as a tar header.
pub fn detect(path: &Path) -> VfsResult<Option<ArchiveFormat>> {
    let mut file = File::open(path).at(path)?;
    let mut head = [0u8; 512];
    let n = read_up_to(&mut file, &mut head).at(path)?;
    let head = &head[..n];
    let by_name = format_of(path);
    let sniffed = if head.starts_with(b"PK\x03\x04")
        || head.starts_with(b"PK\x05\x06")
        || head.starts_with(b"PK\x07\x08")
    {
        Some(ArchiveFormat::Zip)
    } else if head.starts_with(&[b'7', b'z', 0xBC, 0xAF, 0x27, 0x1C]) {
        Some(ArchiveFormat::SevenZip)
    } else if head.starts_with(b"Rar!\x1A\x07") {
        Some(ArchiveFormat::Rar)
    } else if let Some(compression) = compression_of(head) {
        Some(match by_name {
            Some(ArchiveFormat::Tar(_)) => ArchiveFormat::Tar(compression),
            _ if holds_tar(path, compression) => ArchiveFormat::Tar(compression),
            _ => ArchiveFormat::Single(compression),
        })
    } else if is_tar_header(head) {
        Some(ArchiveFormat::Tar(Compression::None))
    } else if is_iso(&mut file) {
        Some(ArchiveFormat::Iso)
    } else {
        None
    };
    Ok(sniffed.or(by_name))
}

/// The compression a stream's first bytes name.
pub(crate) fn compression_of(head: &[u8]) -> Option<Compression> {
    if head.starts_with(&[0x1F, 0x8B]) {
        Some(Compression::Gzip)
    } else if head.len() >= 4 && head.starts_with(b"BZh") && head[3].is_ascii_digit() {
        Some(Compression::Bzip2)
    } else if head.starts_with(&[0xFD, b'7', b'z', b'X', b'Z', 0x00]) {
        Some(Compression::Xz)
    } else if head.starts_with(&[0x28, 0xB5, 0x2F, 0xFD]) {
        Some(Compression::Zstd)
    } else {
        None
    }
}

/// Whether the first block the stream unpacks to is a tar header.
fn holds_tar(path: &Path, compression: Compression) -> bool {
    let Ok(file) = File::open(path) else { return false };
    let Ok(mut reader) = decoder(io::BufReader::new(file), compression) else { return false };
    let mut block = [0u8; 512];
    match read_up_to(&mut reader, &mut block) {
        Ok(512) => is_tar_header(&block),
        _ => false,
    }
}

/// A tar header: the POSIX mark, or an old header whose checksum adds up.
pub(crate) fn is_tar_header(block: &[u8]) -> bool {
    if block.len() < 512 {
        return false;
    }
    if &block[257..262] == b"ustar" {
        return true;
    }
    if block[0] == 0 {
        return false;
    }
    let stored = std::str::from_utf8(&block[148..156])
        .ok()
        .map(|s| s.trim_matches(|c: char| c == '\0' || c == ' '))
        .and_then(|s| u32::from_str_radix(s, 8).ok());
    let Some(stored) = stored else { return false };
    let sum: u32 = block
        .iter()
        .enumerate()
        .map(|(i, &b)| if (148..156).contains(&i) { b' ' as u32 } else { b as u32 })
        .sum();
    sum == stored
}

fn is_iso(file: &mut File) -> bool {
    let mut magic = [0u8; 5];
    file.seek(SeekFrom::Start(ISO_MAGIC_AT)).is_ok()
        && file.read_exact(&mut magic).is_ok()
        && &magic == b"CD001"
}

/// Reads until `buffer` is full or the stream ends; answers the count.
pub(crate) fn read_up_to(reader: &mut dyn Read, buffer: &mut [u8]) -> io::Result<usize> {
    let mut total = 0;
    while total < buffer.len() {
        match reader.read(&mut buffer[total..]) {
            Ok(0) => break,
            Ok(n) => total += n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        }
    }
    Ok(total)
}
