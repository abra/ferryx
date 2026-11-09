//! Viewer members decoded once, with one producer per key. Unnamed files
//! disappear when their last reader closes, including at process exit.
//! One member larger than the budget can stay alone.

use std::collections::{HashMap, VecDeque};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::sync::{Arc, LazyLock, Weak};

use parking_lot::Mutex;

use super::DecodedKey;
use crate::error::{IoAt, VfsError, VfsResult};

const MAX_BYTES: u64 = 512 * 1024 * 1024;
const MAX_MEMBERS: usize = 8;

pub(super) struct Unpacked {
    file: Mutex<File>,
    pub bytes: u64,
}

impl Unpacked {
    pub fn read_range(&self, offset: u64, len: usize) -> VfsResult<Vec<u8>> {
        let want = self.bytes.saturating_sub(offset).min(len as u64) as usize;
        if want == 0 {
            return Ok(Vec::new());
        }
        let at = std::env::temp_dir();
        let mut file = self.file.lock();
        file.seek(SeekFrom::Start(offset)).at(&at)?;
        let mut bytes = Vec::with_capacity(want);
        file.by_ref().take(want as u64).read_to_end(&mut bytes).at(&at)?;
        Ok(bytes)
    }
}

#[derive(Default)]
struct Cache {
    members: VecDeque<(DecodedKey, Arc<Unpacked>)>,
    producers: HashMap<DecodedKey, Weak<Mutex<()>>>,
    bytes: u64,
}

impl Cache {
    fn get(&mut self, key: &DecodedKey) -> Option<Arc<Unpacked>> {
        let at = self.members.iter().position(|(k, _)| k == key)?;
        let item = self.members.remove(at)?;
        let copy = item.1.clone();
        self.members.push_back(item);
        Some(copy)
    }

    fn keep(&mut self, key: DecodedKey, copy: Arc<Unpacked>) {
        self.bytes += copy.bytes;
        self.members.push_back((key, copy));
        while self.members.len() > MAX_MEMBERS || (self.bytes > MAX_BYTES && self.members.len() > 1) {
            if let Some((_, old)) = self.members.pop_front() {
                self.bytes -= old.bytes;
            }
        }
    }
}

static CACHE: LazyLock<Mutex<Cache>> = LazyLock::new(Default::default);

pub(super) fn unpacked(
    key: DecodedKey,
    write: impl FnOnce(&mut File) -> VfsResult<u64>,
) -> VfsResult<Arc<Unpacked>> {
    let producer = {
        let mut cache = CACHE.lock();
        if let Some(copy) = cache.get(&key) {
            return Ok(copy);
        }
        cache.producers.retain(|_, p| p.strong_count() > 0);
        match cache.producers.get(&key).and_then(Weak::upgrade) {
            Some(producer) => producer,
            None => {
                let producer = Arc::new(Mutex::new(()));
                cache.producers.insert(key.clone(), Arc::downgrade(&producer));
                producer
            }
        }
    };
    let _producer = producer.lock();
    if let Some(copy) = CACHE.lock().get(&key) {
        return Ok(copy);
    }
    let mut file = tempfile::tempfile().map_err(|e| VfsError::io(&e, &std::env::temp_dir()))?;
    write(&mut file)?;
    let bytes = file.metadata().at(&std::env::temp_dir())?.len();
    let copy = Arc::new(Unpacked { file: Mutex::new(file), bytes });
    CACHE.lock().keep(key, copy.clone());
    Ok(copy)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn key(path: PathBuf) -> DecodedKey {
        DecodedKey { archive: path, modified: None, len: 1, inner: "file.txt".into(), password: None }
    }

    #[test]
    fn concurrent_readers_share_one_finished_copy() {
        let archive = tempfile::tempdir().unwrap();
        let key = key(archive.path().join("same.zip"));
        let writes = AtomicUsize::new(0);
        let ready = std::sync::Barrier::new(8);
        std::thread::scope(|scope| {
            let jobs: Vec<_> = (0..8)
                .map(|_| {
                    let key = key.clone();
                    let (writes, ready) = (&writes, &ready);
                    scope.spawn(move || {
                        ready.wait();
                        let copy = unpacked(key, |file| {
                            writes.fetch_add(1, Ordering::SeqCst);
                            file.write_all(b"complete").unwrap();
                            Ok(8)
                        })
                        .unwrap();
                        assert_eq!(copy.read_range(0, 8).unwrap(), b"complete");
                        copy
                    })
                })
                .collect();
            let copies: Vec<_> = jobs.into_iter().map(|j| j.join().unwrap()).collect();
            assert!(copies.iter().all(|c| Arc::ptr_eq(c, &copies[0])));
        });
        assert_eq!(writes.load(Ordering::SeqCst), 1);
    }

    fn copy(bytes: u64) -> Arc<Unpacked> {
        let mut file = tempfile::tempfile().unwrap();
        file.write_all(b"readable").unwrap();
        Arc::new(Unpacked { file: Mutex::new(file), bytes })
    }

    #[test]
    fn failed_decode_is_not_published() {
        let archive = tempfile::tempdir().unwrap();
        let key = key(archive.path().join("retry.zip"));
        let failed = unpacked(key.clone(), |file| {
            file.write_all(b"partial").unwrap();
            Err(VfsError::cancelled())
        });
        assert!(failed.is_err());
        let copy = unpacked(key, |file| {
            file.write_all(b"complete").unwrap();
            Ok(8)
        })
        .unwrap();
        assert_eq!(copy.read_range(0, 100).unwrap(), b"complete");
        assert!(copy.read_range(u64::MAX, usize::MAX).unwrap().is_empty());
    }

    #[test]
    fn eviction_keeps_active_readers_and_cleans_up_after_them() {
        let mut cache = Cache::default();
        let first = copy(MAX_BYTES);
        let first_weak = Arc::downgrade(&first);
        cache.keep(key("first".into()), first.clone());
        cache.keep(key("second".into()), copy(1));
        assert_eq!(cache.members.len(), 1);
        assert_eq!(cache.bytes, 1);
        assert_eq!(first.read_range(0, 8).unwrap(), b"readable");
        drop(first);
        assert!(first_weak.upgrade().is_none());
        for i in 0..MAX_MEMBERS + 1 {
            cache.keep(key(i.to_string().into()), copy(1));
        }
        assert_eq!(cache.members.len(), MAX_MEMBERS);
        cache.keep(key("oversized".into()), copy(MAX_BYTES + 1));
        assert_eq!(cache.members.len(), 1);
    }
}
