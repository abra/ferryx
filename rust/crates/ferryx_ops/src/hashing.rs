//! Streamed hashing of files (SHA-256, SHA-1, MD5, BLAKE3) through big
//! buffers, and a small pool of workers that hashes many files at once:
//! reading is the slow part, and a few reads in flight keep a fast disk
//! busy.

use std::fs::File;
use std::io::Read;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::mpsc;

use ferryx_vfs::error::VfsError;
use serde::{Deserialize, Serialize};
use sha1::Digest;

/// What a file is read in.
pub const BUFFER: usize = 1024 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Algorithm {
    Sha256,
    Sha1,
    Md5,
    Blake3,
}

impl Algorithm {
    pub const ALL: [Algorithm; 4] = [Algorithm::Sha256, Algorithm::Sha1, Algorithm::Md5, Algorithm::Blake3];

    /// How many hex digits a hash has.
    pub fn hex_len(self) -> usize {
        match self {
            Algorithm::Sha256 | Algorithm::Blake3 => 64,
            Algorithm::Sha1 => 40,
            Algorithm::Md5 => 32,
        }
    }

    /// The extension of a checksum file of this algorithm (`name.sha256`).
    pub fn extension(self) -> &'static str {
        match self {
            Algorithm::Sha256 => "sha256",
            Algorithm::Sha1 => "sha1",
            Algorithm::Md5 => "md5",
            Algorithm::Blake3 => "b3",
        }
    }

    /// The name a BSD-style checksum line starts with (`SHA256 (a) = …`).
    pub fn tag(self) -> &'static str {
        match self {
            Algorithm::Sha256 => "SHA256",
            Algorithm::Sha1 => "SHA1",
            Algorithm::Md5 => "MD5",
            Algorithm::Blake3 => "BLAKE3",
        }
    }
}

/// One hash under way.
pub enum Hasher {
    Sha256(sha2::Sha256),
    Sha1(sha1::Sha1),
    Md5(md5::Md5),
    Blake3(Box<blake3::Hasher>),
}

impl Hasher {
    pub fn new(algorithm: Algorithm) -> Hasher {
        match algorithm {
            Algorithm::Sha256 => Hasher::Sha256(sha2::Sha256::new()),
            Algorithm::Sha1 => Hasher::Sha1(sha1::Sha1::new()),
            Algorithm::Md5 => Hasher::Md5(md5::Md5::new()),
            Algorithm::Blake3 => Hasher::Blake3(Box::new(blake3::Hasher::new())),
        }
    }

    pub fn update(&mut self, bytes: &[u8]) {
        match self {
            Hasher::Sha256(h) => h.update(bytes),
            Hasher::Sha1(h) => h.update(bytes),
            Hasher::Md5(h) => h.update(bytes),
            Hasher::Blake3(h) => {
                h.update(bytes);
            }
        }
    }

    /// The hash in lower-case hex.
    pub fn finish(self) -> String {
        match self {
            Hasher::Sha256(h) => hex(&h.finalize()),
            Hasher::Sha1(h) => hex(&h.finalize()),
            Hasher::Md5(h) => hex(&h.finalize()),
            Hasher::Blake3(h) => hex(h.finalize().as_bytes()),
        }
    }
}

/// `bytes` in lower-case hex.
pub fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push(DIGITS[(b >> 4) as usize] as char);
        out.push(DIGITS[(b & 0xf) as usize] as char);
    }
    out
}

/// Why a file has no hash.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HashError {
    Io(VfsError),
    Cancelled,
}

/// The hash of the file at `path`, or of its first `limit` bytes; reads
/// through `buffer` and calls `on_bytes` with each read's length. Stops
/// when `cancel` is set.
pub fn hash_file(
    path: &Path,
    algorithm: Algorithm,
    limit: Option<u64>,
    buffer: &mut [u8],
    cancel: &AtomicBool,
    on_bytes: &mut dyn FnMut(u64),
) -> Result<String, HashError> {
    let mut file = File::open(path).map_err(|e| HashError::Io(VfsError::io(&e, path)))?;
    let mut hasher = Hasher::new(algorithm);
    let mut left = limit.unwrap_or(u64::MAX);
    while left > 0 {
        if cancel.load(Ordering::Relaxed) {
            return Err(HashError::Cancelled);
        }
        let want = buffer.len().min(usize::try_from(left).unwrap_or(usize::MAX));
        let read = match file.read(&mut buffer[..want]) {
            Ok(0) => break,
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(HashError::Io(VfsError::io(&e, path))),
        };
        hasher.update(&buffer[..read]);
        left -= read as u64;
        on_bytes(read as u64);
    }
    Ok(hasher.finish())
}

/// Workers for reading many files at once: a few, as the reads, not the
/// processors, are what is waited on.
pub fn workers() -> usize {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(2).clamp(1, 4)
}

/// Runs `work` over every job on `workers` threads, each with a buffer of
/// its own, and hands each result to `on_event` on the calling thread as
/// it comes (not in order), with the job's index; `None` about every
/// 50 ms while nothing finishes, for progress reports. Jobs not started
/// yet are skipped once `cancel` is set.
pub fn parallel<J, R>(
    jobs: &[J],
    workers: usize,
    cancel: &AtomicBool,
    work: impl Fn(&J, &mut [u8]) -> R + Sync,
    mut on_event: impl FnMut(Option<(usize, R)>),
) where
    J: Sync,
    R: Send,
{
    if jobs.is_empty() {
        return;
    }
    let next = AtomicUsize::new(0);
    let (sender, receiver) = mpsc::channel::<(usize, R)>();
    std::thread::scope(|scope| {
        for _ in 0..workers.max(1).min(jobs.len()) {
            let sender = sender.clone();
            let next = &next;
            let work = &work;
            scope.spawn(move || {
                let mut buffer = vec![0u8; BUFFER];
                loop {
                    if cancel.load(Ordering::Relaxed) {
                        break;
                    }
                    let index = next.fetch_add(1, Ordering::Relaxed);
                    let Some(job) = jobs.get(index) else { break };
                    let result = work(job, &mut buffer);
                    if sender.send((index, result)).is_err() {
                        break;
                    }
                }
            });
        }
        drop(sender);
        loop {
            match receiver.recv_timeout(std::time::Duration::from_millis(50)) {
                Ok(done) => on_event(Some(done)),
                Err(mpsc::RecvTimeoutError::Timeout) => on_event(None),
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hash_of(bytes: &[u8], algorithm: Algorithm) -> String {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("f");
        std::fs::write(&path, bytes).unwrap();
        let mut buffer = vec![0u8; 7];
        let mut seen = 0u64;
        let hash =
            hash_file(&path, algorithm, None, &mut buffer, &AtomicBool::new(false), &mut |n| seen += n)
                .unwrap();
        assert_eq!(seen, bytes.len() as u64);
        assert_eq!(hash.len(), algorithm.hex_len());
        hash
    }

    #[test]
    fn known_digests() {
        assert_eq!(
            hash_of(b"abc", Algorithm::Sha256),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(hash_of(b"abc", Algorithm::Sha1), "a9993e364706816aba3e25717850c26c9cd0d89d");
        assert_eq!(hash_of(b"abc", Algorithm::Md5), "900150983cd24fb0d6963f7d28e17f72");
        assert_eq!(
            hash_of(b"abc", Algorithm::Blake3),
            "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85"
        );
        assert_eq!(hash_of(b"", Algorithm::Md5), "d41d8cd98f00b204e9800998ecf8427e");
    }

    #[test]
    fn a_limit_hashes_the_start_only() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("f");
        std::fs::write(&path, b"abcdef").unwrap();
        let mut buffer = vec![0u8; BUFFER];
        let start =
            hash_file(&path, Algorithm::Md5, Some(3), &mut buffer, &AtomicBool::new(false), &mut |_| {})
                .unwrap();
        assert_eq!(start, "900150983cd24fb0d6963f7d28e17f72");
    }

    #[test]
    fn errors_and_cancellation() {
        let mut buffer = vec![0u8; 16];
        let missing = hash_file(
            Path::new("/no/such/file"),
            Algorithm::Sha1,
            None,
            &mut buffer,
            &AtomicBool::new(false),
            &mut |_| {},
        );
        assert!(matches!(missing, Err(HashError::Io(e)) if e.kind == ferryx_vfs::VfsErrorKind::NotFound));
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("f");
        std::fs::write(&path, b"x").unwrap();
        let cancelled =
            hash_file(&path, Algorithm::Sha1, None, &mut buffer, &AtomicBool::new(true), &mut |_| {});
        assert_eq!(cancelled, Err(HashError::Cancelled));
    }

    #[test]
    fn parallel_hands_back_every_result() {
        let jobs: Vec<u32> = (0..100).collect();
        let mut seen = vec![false; jobs.len()];
        parallel(
            &jobs,
            4,
            &AtomicBool::new(false),
            |j, _| j * 2,
            |event| {
                if let Some((i, r)) = event {
                    assert_eq!(r, jobs[i] * 2);
                    seen[i] = true;
                }
            },
        );
        assert!(seen.iter().all(|s| *s));
        // Cancelled before it starts: nothing runs.
        let mut ran = 0;
        parallel(
            &jobs,
            4,
            &AtomicBool::new(true),
            |j, _| *j,
            |event| {
                if event.is_some() {
                    ran += 1;
                }
            },
        );
        assert_eq!(ran, 0);
    }
}
