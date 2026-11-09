use std::fs;
use std::sync::{mpsc, Arc, Barrier};
use std::thread;
use std::time::{Duration, Instant};

use super::*;
use crate::archive::ArchiveIndex;
use crate::VfsErrorKind;

fn zip(path: &Path, contents: &[u8]) {
    let mut zip = zip::ZipWriter::new(File::create(path).unwrap());
    zip.start_file("books/book.epub", zip::write::SimpleFileOptions::default()).unwrap();
    zip.write_all(contents).unwrap();
    zip.finish().unwrap();
}

#[test]
fn native_path_is_borrowed_and_close_before_prepare_does_no_io() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("source.epub");
    fs::write(&path, b"source").unwrap();
    let file = PreviewFile::new(Location::native(&path));
    assert_eq!(file.prepare().unwrap(), path);
    file.close().unwrap();
    file.close().unwrap();
    assert_eq!(file.prepare().unwrap_err().kind, VfsErrorKind::Cancelled);
    assert_eq!(fs::read(&path).unwrap(), b"source");

    let pending = PreviewFile::new(Location::Archive { archive: path.clone(), inner: "missing".into() });
    pending.close().unwrap();
    assert_eq!(pending.prepare().unwrap_err().kind, VfsErrorKind::Cancelled);
    assert_eq!(fs::read(path).unwrap(), b"source");
}

#[test]
fn archive_copies_are_private_and_owned_until_close_or_drop() {
    let directory = tempfile::tempdir().unwrap();
    let archive = directory.path().join("source.zip");
    zip(&archive, b"epub contents");
    let location = Location::Archive { archive: archive.clone(), inner: "books/book.epub".into() };
    let first = PreviewFile::new(location.clone());
    let second = PreviewFile::new(location);
    let one = first.prepare().unwrap();
    let two = second.prepare().unwrap();
    assert_eq!(first.prepare().unwrap(), one);
    assert_ne!(one, two);
    assert_eq!(one.file_name().unwrap(), "book.epub");
    assert_eq!(fs::read(&one).unwrap(), b"epub contents");
    first.close().unwrap();
    assert!(!one.parent().unwrap().exists());
    assert_eq!(fs::read(&two).unwrap(), b"epub contents");
    drop(second);
    assert!(!two.parent().unwrap().exists());
    assert!(archive.exists());
}

#[test]
fn failed_staging_removes_partial_bytes_and_cannot_escape_its_directory() {
    let mut partial = PathBuf::new();
    let result = stage("../../outside\\book.epub", &crate::remote::never, |file, path| {
        partial = path.to_owned();
        file.write_all(b"partial").unwrap();
        Err(VfsError::unsupported("decoder failed"))
    });
    assert_eq!(result.err().unwrap().kind, VfsErrorKind::Unsupported);
    assert_eq!(partial.file_name().unwrap(), "book.epub");
    assert!(!partial.parent().unwrap().exists());
}

#[test]
fn close_waits_for_preparation_and_never_publishes_its_late_path() {
    let file = Arc::new(PreviewFile::new(Location::native("unused")));
    let release = Arc::new(Barrier::new(2));
    let (started, path) = mpsc::channel();
    let worker = {
        let file = file.clone();
        let release = release.clone();
        thread::spawn(move || {
            file.prepare_with(|| {
                stage("book.pdf", &|| file.stopped(), |out, path| {
                    out.write_all(b"partial").unwrap();
                    started.send(path.to_owned()).unwrap();
                    release.wait();
                    Ok(())
                })
            })
        })
    };
    let partial = path.recv_timeout(Duration::from_secs(5)).unwrap();
    let (closed, close_done) = mpsc::channel();
    let closer = {
        let file = file.clone();
        thread::spawn(move || closed.send(file.close()).unwrap())
    };
    let deadline = Instant::now() + Duration::from_secs(5);
    while !file.stopped() {
        assert!(Instant::now() < deadline);
        thread::yield_now();
    }
    assert!(matches!(close_done.try_recv(), Err(mpsc::TryRecvError::Empty)));
    release.wait();
    assert_eq!(worker.join().unwrap().unwrap_err().kind, VfsErrorKind::Cancelled);
    close_done.recv_timeout(Duration::from_secs(5)).unwrap().unwrap();
    closer.join().unwrap();
    assert!(!partial.parent().unwrap().exists());
    assert_eq!(file.prepare().unwrap_err().kind, VfsErrorKind::Cancelled);
}

#[test]
fn concurrent_requests_have_one_producer() {
    let file = Arc::new(PreviewFile::new(Location::native("unused")));
    let (ready, started) = mpsc::channel();
    let release = Arc::new(Barrier::new(2));
    let first = {
        let file = file.clone();
        let release = release.clone();
        thread::spawn(move || {
            file.prepare_with(|| {
                stage("book.pdf", &crate::remote::never, |out, _| {
                    ready.send(()).unwrap();
                    release.wait();
                    out.write_all(b"one producer").unwrap();
                    Ok(())
                })
            })
        })
    };
    started.recv_timeout(Duration::from_secs(5)).unwrap();
    let second = {
        let file = file.clone();
        thread::spawn(move || file.prepare_with(|| panic!("second producer")))
    };
    release.wait();
    let path = first.join().unwrap().unwrap();
    assert_eq!(second.join().unwrap().unwrap(), path);
    assert_eq!(fs::read(&path).unwrap(), b"one producer");
    file.close().unwrap();
    assert!(!path.exists());
}

#[test]
fn archive_decode_stops_before_materializing_the_whole_member() {
    use std::sync::atomic::AtomicUsize;
    let directory = tempfile::tempdir().unwrap();
    let archive = directory.path().join("source.zip");
    let input = vec![42; 2 * 1024 * 1024];
    zip(&archive, &input);
    let index = ArchiveIndex::open(&archive).unwrap();
    let checks = AtomicUsize::new(0);
    let stop = || checks.fetch_add(1, Ordering::Relaxed) >= 5;
    let mut output = Vec::new();
    let error = index.read_member_to_until("books/book.epub", None, &mut output, &stop).unwrap_err();
    assert_eq!(error.kind, VfsErrorKind::Cancelled);
    assert!(!output.is_empty());
    assert!(output.len() < input.len());
}

#[test]
fn solid_archive_cancels_while_skipping_a_previous_member() {
    use sevenz_rust2::{ArchiveEntry, ArchiveWriter, SourceReader};
    use std::sync::atomic::AtomicUsize;

    let directory = tempfile::tempdir().unwrap();
    let archive = directory.path().join("source.7z");
    let preceding = vec![42; 2 * 1024 * 1024];
    let mut writer = ArchiveWriter::create(&archive).unwrap();
    writer.set_encrypt_header(false);
    writer
        .push_archive_entries(
            vec![ArchiveEntry::new_file("large.bin"), ArchiveEntry::new_file("book.epub")],
            vec![SourceReader::new(preceding.as_slice()), SourceReader::new(&b"book"[..])],
        )
        .unwrap();
    writer.finish().unwrap();
    let index = ArchiveIndex::open(&archive).unwrap();
    let checks = AtomicUsize::new(0);
    let stop = || checks.fetch_add(1, Ordering::Relaxed) >= 5;
    let mut out = Vec::new();
    let error = index.read_member_to_until("book.epub", None, &mut out, &stop).unwrap_err();
    assert_eq!(error.kind, VfsErrorKind::Cancelled);
    assert!(out.is_empty());
}

#[test]
fn a_remote_preview_uses_a_local_copy_and_preserves_the_server_file() {
    use crate::remote::{AuthMethod, ConnectSpec, Protocol, ServerAddress};
    use ferryx_test_servers::dav::{DavOptions, DavServer};

    let server = DavServer::start(DavOptions { user: None, ..DavOptions::default() });
    let original = server.root.path().join("book.pdf");
    let bytes = vec![37; COPY_BUFFER * 3 + 7];
    fs::write(&original, &bytes).unwrap();
    let mut address = ServerAddress::new(Protocol::Dav, "127.0.0.1", "");
    address.port = server.port;
    let connected =
        connection::connect(ConnectSpec { address, auth: AuthMethod::Password }, &crate::remote::never)
            .unwrap();
    let key = connected.key().to_owned();
    let lease = PreviewFile::new(Location::Remote { server: key.clone(), path: "/book.pdf".into() });
    let copy = lease.prepare().unwrap();
    assert_ne!(copy, original);
    assert_eq!(fs::read(&copy).unwrap(), bytes);
    lease.close().unwrap();
    assert!(!copy.parent().unwrap().exists());
    assert_eq!(fs::read(original).unwrap(), bytes);
    connection::disconnect(&key);
}

struct Remote {
    left: usize,
    calls: usize,
    cancel_on_read: Option<Arc<AtomicBool>>,
}

impl RemoteRead for Remote {
    fn read(&mut self, buf: &mut [u8], stop: Stop) -> VfsResult<usize> {
        check(stop)?;
        assert_eq!(buf.len(), COPY_BUFFER);
        self.calls += 1;
        let count = self.left.min(buf.len());
        buf[..count].fill(12);
        self.left -= count;
        if let Some(cancel) = &self.cancel_on_read {
            cancel.store(true, Ordering::Release);
        }
        Ok(count)
    }
}

#[test]
fn remote_copy_is_bounded_and_drops_bytes_received_after_cancellation() {
    let mut reader = Remote { left: COPY_BUFFER * 3 + 5, calls: 0, cancel_on_read: None };
    let mut out = Vec::new();
    copy_remote(&mut reader, &mut out, Path::new("preview"), &crate::remote::never).unwrap();
    assert_eq!(out.len(), COPY_BUFFER * 3 + 5);
    assert_eq!(reader.calls, 5);
    let cancel = Arc::new(AtomicBool::new(false));
    let mut reader = Remote { left: COPY_BUFFER * 3, calls: 0, cancel_on_read: Some(cancel.clone()) };
    let stop = || cancel.load(Ordering::Acquire);
    let mut out = Vec::new();
    let error = copy_remote(&mut reader, &mut out, Path::new("preview"), &stop).unwrap_err();
    assert_eq!(error.kind, VfsErrorKind::Cancelled);
    assert!(out.is_empty());
    assert_eq!(reader.calls, 1);
}
