use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};

use super::*;

// ─── Writers for the formats the tests read ───

fn make_zip(dir: &Path) -> PathBuf {
    let path = dir.join("a.zip");
    let mut zip = zip::ZipWriter::new(File::create(&path).unwrap());
    let opts = zip::write::SimpleFileOptions::default();
    zip.start_file("top.txt", opts).unwrap();
    zip.write_all(b"top").unwrap();
    zip.start_file("dir/inner.txt", opts).unwrap();
    zip.write_all(b"inner text").unwrap();
    zip.start_file("dir/.secret", opts).unwrap();
    zip.write_all(b"s").unwrap();
    zip.add_directory("empty/", opts).unwrap();
    zip.finish().unwrap();
    path
}

/// A tar of `x.txt` (`xx`) and `d/y.txt` (`yy`) compressed with
/// `compression`, written at `path`.
fn make_tar(path: &Path, compression: Compression) -> PathBuf {
    let mut tar_bytes = Vec::new();
    {
        let mut tar = tar::Builder::new(&mut tar_bytes);
        for (name, data) in [("./x.txt", &b"xx"[..]), ("d/y.txt", &b"yy"[..])] {
            let mut header = tar::Header::new_gnu();
            header.set_size(data.len() as u64);
            header.set_mode(0o644);
            header.set_mtime(1_700_000_000);
            header.set_cksum();
            tar.append_data(&mut header, name, data).unwrap();
        }
        let mut header = tar::Header::new_gnu();
        header.set_entry_type(tar::EntryType::Symlink);
        header.set_size(0);
        header.set_mode(0o777);
        header.set_cksum();
        tar.append_link(&mut header, "d/link", "y.txt").unwrap();
        tar.finish().unwrap();
    }
    fs::write(path, compress(&tar_bytes, compression)).unwrap();
    path.to_path_buf()
}

fn compress(data: &[u8], compression: Compression) -> Vec<u8> {
    match compression {
        Compression::None => data.to_vec(),
        Compression::Gzip => {
            let mut e = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
            e.write_all(data).unwrap();
            e.finish().unwrap()
        }
        Compression::Bzip2 => {
            let mut e = bzip2::write::BzEncoder::new(Vec::new(), bzip2::Compression::fast());
            e.write_all(data).unwrap();
            e.finish().unwrap()
        }
        Compression::Xz => {
            let mut e = lzma_rust2::XzWriter::new(Vec::new(), lzma_rust2::XzOptions::with_preset(1)).unwrap();
            e.write_all(data).unwrap();
            e.finish().unwrap()
        }
        Compression::Zstd => zstd::encode_all(data, 1).unwrap(),
    }
}

/// A 7z of `a.txt`, `sub/b.txt` and `sub/c.txt`, solid, encrypted with
/// `password` when given (and its member list too, with `hide_names`).
fn make_7z(path: &Path, password: Option<&str>, hide_names: bool) -> PathBuf {
    use sevenz_rust2::encoder_options::AesEncoderOptions;
    use sevenz_rust2::{ArchiveEntry, ArchiveWriter, EncoderMethod, Password, SourceReader};
    let mut writer = ArchiveWriter::create(path).unwrap();
    match password {
        Some(password) => {
            writer.set_content_methods(vec![
                AesEncoderOptions::new(Password::new(password)).into(),
                EncoderMethod::LZMA2.into(),
            ]);
            writer.set_encrypt_header(hide_names);
        }
        None => writer.set_encrypt_header(false),
    }
    let entries = vec![
        ArchiveEntry::new_file("a.txt"),
        ArchiveEntry::new_file("sub/b.txt"),
        ArchiveEntry::new_file("sub/c.txt"),
    ];
    let data: Vec<&[u8]> = vec![b"alpha", b"bravo bravo", b"charlie"];
    writer.push_archive_entries(entries, data.into_iter().map(SourceReader::new).collect()).unwrap();
    writer.push_archive_entry::<&[u8]>(ArchiveEntry::new_directory("empty"), None).unwrap();
    writer.finish().unwrap();
    path.to_path_buf()
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 };
        }
    }
    !crc
}

fn vint(mut value: u64, out: &mut Vec<u8>) {
    loop {
        let byte = (value & 0x7F) as u8;
        value >>= 7;
        if value == 0 {
            out.push(byte);
            return;
        }
        out.push(byte | 0x80);
    }
}

/// A RAR5 header: CRC32, size, then `body` (type, flags and the rest).
fn rar_block(body: &[u8]) -> Vec<u8> {
    let mut sized = Vec::new();
    vint(body.len() as u64, &mut sized);
    sized.extend_from_slice(body);
    let mut out = crc32(&sized).to_le_bytes().to_vec();
    out.extend(sized);
    out
}

/// A RAR5 archive of stored (uncompressed) files, as `rar -m0` writes it.
fn make_rar(path: &Path, files: &[(&str, &[u8])]) -> PathBuf {
    let mut out = b"Rar!\x1A\x07\x01\x00".to_vec();
    let mut main = Vec::new();
    vint(1, &mut main); // main archive header
    vint(0, &mut main); // header flags
    vint(0, &mut main); // archive flags
    out.extend(rar_block(&main));
    for (name, data) in files {
        let mut file = Vec::new();
        vint(2, &mut file); // file header
        vint(0x0002, &mut file); // a data area follows
        vint(data.len() as u64, &mut file); // data size
        vint(0x0002 | 0x0004, &mut file); // mtime and CRC32 present
        vint(data.len() as u64, &mut file); // unpacked size
        vint(0o644, &mut file); // attributes
        file.extend_from_slice(&1_700_000_000u32.to_le_bytes());
        file.extend_from_slice(&crc32(data).to_le_bytes());
        vint(0, &mut file); // version 0, not solid, stored
        vint(1, &mut file); // host: Unix
        vint(name.len() as u64, &mut file);
        file.extend_from_slice(name.as_bytes());
        out.extend(rar_block(&file));
        out.extend_from_slice(data);
    }
    let mut end = Vec::new();
    vint(5, &mut end);
    vint(0, &mut end);
    vint(0, &mut end);
    out.extend(rar_block(&end));
    fs::write(path, out).unwrap();
    path.to_path_buf()
}

/// An ISO 9660 image with a Joliet tree: `readme.txt` at the root and
/// `dir/Long File Name.txt`.
fn make_iso(path: &Path) -> PathBuf {
    const S: usize = 2048;
    fn record(extent: u32, len: u32, dir: bool, name: &[u8]) -> Vec<u8> {
        let pad = if name.len() % 2 == 0 { 1 } else { 0 };
        let size = 33 + name.len() + pad;
        let mut r = vec![0u8; size];
        r[0] = size as u8;
        r[2..6].copy_from_slice(&extent.to_le_bytes());
        r[6..10].copy_from_slice(&extent.to_be_bytes());
        r[10..14].copy_from_slice(&len.to_le_bytes());
        r[14..18].copy_from_slice(&len.to_be_bytes());
        r[18..25].copy_from_slice(&[124, 6, 15, 12, 30, 0, 0]);
        r[25] = if dir { 2 } else { 0 };
        r[28] = 1;
        r[31] = 1;
        r[32] = name.len() as u8;
        r[33..33 + name.len()].copy_from_slice(name);
        r
    }
    fn ucs2(text: &str) -> Vec<u8> {
        text.encode_utf16().flat_map(|u| u.to_be_bytes()).collect()
    }
    fn dir_sector(own: u32, parent: u32, children: Vec<Vec<u8>>) -> Vec<u8> {
        let mut s = record(own, S as u32, true, &[0]);
        s.extend(record(parent, S as u32, true, &[1]));
        for c in children {
            s.extend(c);
        }
        s.resize(S, 0);
        s
    }
    let readme = b"read me";
    let long = b"a long name";
    let mut image = vec![0u8; 16 * S];
    let descriptor = |kind: u8, root: u32| {
        let mut d = vec![0u8; S];
        d[0] = kind;
        d[1..6].copy_from_slice(b"CD001");
        d[6] = 1;
        if kind == 2 {
            d[88..91].copy_from_slice(b"%/E");
        }
        if kind != 255 {
            d[156..190].copy_from_slice(&record(root, S as u32, true, &[0]));
        }
        d
    };
    image.extend(descriptor(1, 19));
    image.extend(descriptor(2, 21));
    image.extend(descriptor(255, 0));
    image.extend(dir_sector(
        19,
        19,
        vec![record(20, S as u32, true, b"DIR"), record(23, readme.len() as u32, false, b"README.TXT;1")],
    ));
    image.extend(dir_sector(20, 19, vec![record(24, long.len() as u32, false, b"LONG_FIL.TXT;1")]));
    image.extend(dir_sector(
        21,
        21,
        vec![
            record(22, S as u32, true, &ucs2("dir")),
            record(23, readme.len() as u32, false, &ucs2("readme.txt;1")),
        ],
    ));
    image.extend(dir_sector(
        22,
        21,
        vec![record(24, long.len() as u32, false, &ucs2("Long File Name.txt;1"))],
    ));
    let mut data = readme.to_vec();
    data.resize(S, 0);
    image.extend(data);
    let mut data = long.to_vec();
    data.resize(S, 0);
    image.extend(data);
    fs::write(path, image).unwrap();
    path.to_path_buf()
}

/// Every file member's path and bytes, through [`ArchiveIndex::extract_members`].
#[derive(Default)]
struct Collect {
    current: Vec<u8>,
    got: Vec<(String, Vec<u8>)>,
    failures: Vec<(String, VfsErrorKind)>,
    skip: Vec<String>,
}

impl MemberSink for Collect {
    fn begin(&mut self, member: &Member) -> Result<bool, Stop> {
        self.current.clear();
        Ok(!self.skip.contains(&member.path))
    }

    fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        self.current.extend_from_slice(bytes);
        Ok(())
    }

    fn end(&mut self, member: &Member, outcome: VfsResult<u64>) -> Result<(), Stop> {
        match outcome {
            Ok(_) => self.got.push((member.path.clone(), std::mem::take(&mut self.current))),
            Err(e) => self.failures.push((member.path.clone(), e.kind)),
        }
        Ok(())
    }
}

fn names(entries: &[Entry]) -> Vec<&str> {
    entries.iter().map(|e| e.name.as_str()).collect()
}

// ─── Tests ───

#[test]
fn zip_lists_and_reads() {
    let dir = tempfile::tempdir().unwrap();
    let path = make_zip(dir.path());
    let index = ArchiveIndex::open(&path).unwrap();
    assert_eq!(index.format, ArchiveFormat::Zip);
    let root = index.list("", true, false).unwrap();
    assert_eq!(names(&root), ["..", "dir", "empty", "top.txt"]);
    assert!(root[1].is_dir);
    let inside = index.list("dir", true, false).unwrap();
    assert_eq!(names(&inside), ["..", "inner.txt"]);
    assert_eq!(inside[0].path, PathBuf::from(""));
    assert_eq!(index.list("dir", false, true).unwrap().len(), 2);
    assert_eq!(index.read("dir/inner.txt").unwrap(), b"inner text");
    assert_eq!(index.read_range("dir/inner.txt", 6, 100, None).unwrap(), b"text");
    assert!(index.read("dir").is_err());
    assert_eq!(index.list("top.txt", true, false).unwrap_err().kind, VfsErrorKind::NotADirectory);
    let out = tempfile::tempdir().unwrap();
    let extracted = index.extract("dir", out.path()).unwrap();
    assert!(extracted.join("inner.txt").exists());
    assert!(extracted.join(".secret").exists());
    let one = index.extract("top.txt", out.path()).unwrap();
    assert_eq!(fs::read(one).unwrap(), b"top");
    assert!(!index.is_stale());
    assert_eq!(index.top_level().count(), 3);
    assert_eq!(index.totals(&["dir".to_string()]), (11, 2));
}

#[test]
fn every_tar_compression_lists_reads_and_streams() {
    let dir = tempfile::tempdir().unwrap();
    for (name, compression) in [
        ("t.tar", Compression::None),
        ("t.tar.gz", Compression::Gzip),
        ("t.tbz2", Compression::Bzip2),
        ("t.tar.xz", Compression::Xz),
        ("t.tzst", Compression::Zstd),
    ] {
        let path = make_tar(&dir.path().join(name), compression);
        let index = ArchiveIndex::open(&path).unwrap();
        assert_eq!(index.format, ArchiveFormat::Tar(compression), "{name}");
        assert_eq!(names(&index.list("", false, false).unwrap()), ["d", "x.txt"], "{name}");
        assert_eq!(index.read("d/y.txt").unwrap(), b"yy", "{name}");
        let link = index.member("d/link").unwrap();
        assert!(link.is_symlink);
        assert_eq!(link.link.as_deref(), Some("y.txt"));
        let mut sink = Collect::default();
        index.extract_members(&["x.txt".into(), "d/y.txt".into()], None, &mut sink).unwrap();
        assert_eq!(
            sink.got,
            [("x.txt".to_string(), b"xx".to_vec()), ("d/y.txt".to_string(), b"yy".to_vec())]
        );
    }
}

#[test]
fn detection_reads_the_bytes_before_the_name() {
    let dir = tempfile::tempdir().unwrap();
    // A tar.gz under another name, and a .gz that holds a tar.
    let misnamed = make_tar(&dir.path().join("data.bin"), Compression::Gzip);
    assert_eq!(detect(&misnamed).unwrap(), Some(ArchiveFormat::Tar(Compression::Gzip)));
    let gz_tar = make_tar(&dir.path().join("bundle.gz"), Compression::Gzip);
    assert_eq!(detect(&gz_tar).unwrap(), Some(ArchiveFormat::Tar(Compression::Gzip)));
    // A zip named .7z is a zip.
    let zip = make_zip(dir.path());
    let renamed = dir.path().join("really-a-zip.7z");
    fs::rename(&zip, &renamed).unwrap();
    assert_eq!(detect(&renamed).unwrap(), Some(ArchiveFormat::Zip));
    // Text is no archive, whatever it is called.
    let text = dir.path().join("notes.txt");
    fs::write(&text, b"hello").unwrap();
    assert_eq!(detect(&text).unwrap(), None);
    assert_eq!(ArchiveIndex::open(&text).unwrap_err().kind, VfsErrorKind::Unsupported);
    assert_eq!(format_of(Path::new("a.TGZ")), Some(ArchiveFormat::Tar(Compression::Gzip)));
    assert_eq!(format_of(Path::new("a.tar.zst")), Some(ArchiveFormat::Tar(Compression::Zstd)));
    assert_eq!(format_of(Path::new("log.xz")), Some(ArchiveFormat::Single(Compression::Xz)));
    assert_eq!(format_of(Path::new("a.txt")), None);
    assert!(is_archive(Path::new("disc.iso")));
}

#[test]
fn one_compressed_file_is_an_archive_of_one() {
    let dir = tempfile::tempdir().unwrap();
    let text = b"line one\nline two\n".repeat(100);
    for (name, compression) in [
        ("log.txt.gz", Compression::Gzip),
        ("log.txt.bz2", Compression::Bzip2),
        ("log.txt.xz", Compression::Xz),
        ("log.txt.zst", Compression::Zstd),
    ] {
        let path = dir.path().join(name);
        fs::write(&path, compress(&text, compression)).unwrap();
        let index = ArchiveIndex::open(&path).unwrap();
        assert_eq!(index.format, ArchiveFormat::Single(compression), "{name}");
        let rows = index.list("", false, false).unwrap();
        assert_eq!(names(&rows), ["log.txt"], "{name}");
        assert_eq!(index.read("log.txt").unwrap(), text, "{name}");
        // gzip and zstd say the size; the others are measured once read.
        assert_eq!(index.member_size("log.txt", None).unwrap(), text.len() as u64, "{name}");
        assert_eq!(index.read_range("log.txt", 5, 3, None).unwrap(), b"one", "{name}");
    }
}

#[test]
fn seven_zip_solid_blocks_stream_once() {
    let dir = tempfile::tempdir().unwrap();
    let path = make_7z(&dir.path().join("s.7z"), None, false);
    let index = ArchiveIndex::open(&path).unwrap();
    assert_eq!(index.format, ArchiveFormat::SevenZip);
    assert!(!index.encrypted);
    assert_eq!(names(&index.list("", false, false).unwrap()), ["a.txt", "empty", "sub"]);
    assert_eq!(index.read("sub/c.txt").unwrap(), b"charlie");
    // The first member is passed by, the others delivered in order.
    let mut sink = Collect::default();
    index.extract_members(&["sub/b.txt".into(), "sub/c.txt".into()], None, &mut sink).unwrap();
    assert_eq!(
        sink.got,
        [("sub/b.txt".to_string(), b"bravo bravo".to_vec()), ("sub/c.txt".to_string(), b"charlie".to_vec())]
    );
    // A sink that passes one by still gets the next one whole.
    let mut sink = Collect { skip: vec!["sub/b.txt".into()], ..Default::default() };
    index.extract_members(&["sub/b.txt".into(), "sub/c.txt".into()], None, &mut sink).unwrap();
    assert_eq!(sink.got, [("sub/c.txt".to_string(), b"charlie".to_vec())]);
}

#[test]
fn seven_zip_passwords() {
    let dir = tempfile::tempdir().unwrap();
    let path = make_7z(&dir.path().join("locked.7z"), Some("secret"), false);
    let index = ArchiveIndex::open(&path).unwrap();
    assert!(index.encrypted);
    assert!(!index.headers_encrypted);
    assert_eq!(index.read("a.txt").unwrap_err().kind, VfsErrorKind::PasswordRequired);
    assert_eq!(index.check_password("wrong").unwrap_err().kind, VfsErrorKind::WrongPassword);
    index.check_password("secret").unwrap();
    assert_eq!(index.read_with("a.txt", Some("secret")).unwrap(), b"alpha");

    let hidden = make_7z(&dir.path().join("hidden.7z"), Some("secret"), true);
    assert_eq!(ArchiveIndex::open(&hidden).unwrap_err().kind, VfsErrorKind::PasswordRequired);
    assert_eq!(ArchiveIndex::open_with(&hidden, Some("nope")).unwrap_err().kind, VfsErrorKind::WrongPassword);
    let index = ArchiveIndex::open_with(&hidden, Some("secret")).unwrap();
    assert!(index.headers_encrypted);
    assert_eq!(names(&index.list("sub", false, false).unwrap()), ["b.txt", "c.txt"]);
    assert_eq!(index.read_with("sub/b.txt", Some("secret")).unwrap(), b"bravo bravo");
}

/// A wrong password decrypts to random bytes, which the LZMA decoders
/// once spun on forever about one time in ten, and which could also read
/// as a stream that ends early and so pass for the right one: each try
/// here must end, and end refused. (Every archive has a salt of its own,
/// so the garbage differs from one to the next.)
#[test]
fn wrong_passwords_always_end_refused() {
    let dir = tempfile::tempdir().unwrap();
    for i in 0..50 {
        let path = make_7z(&dir.path().join(format!("locked-{i}.7z")), Some("secret"), i % 2 == 0);
        let (sent, got) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let refused = match ArchiveIndex::open_with(&path, Some("wrong")) {
                Ok(index) => index.check_password("wrong").err().map(|e| e.kind),
                Err(error) => Some(error.kind),
            };
            let _ = sent.send(refused);
        });
        let kind = got
            .recv_timeout(std::time::Duration::from_secs(10))
            .unwrap_or_else(|_| panic!("try {i} with a wrong password did not end"));
        assert_eq!(kind, Some(VfsErrorKind::WrongPassword), "try {i}");
    }
}

#[test]
fn rar_lists_and_reads() {
    let dir = tempfile::tempdir().unwrap();
    let path = make_rar(&dir.path().join("r.rar"), &[("doc/a.txt", b"rar alpha"), ("b.txt", b"rar bravo")]);
    let index = ArchiveIndex::open(&path).unwrap();
    assert_eq!(index.format, ArchiveFormat::Rar);
    assert_eq!(names(&index.list("", false, false).unwrap()), ["b.txt", "doc"]);
    let member = index.member("doc/a.txt").unwrap();
    assert_eq!(member.size, 9);
    assert_eq!(member.modified_ms, Some(1_700_000_000_000));
    assert_eq!(index.read("doc/a.txt").unwrap(), b"rar alpha");
    let mut sink = Collect::default();
    index.extract_members(&["b.txt".into(), "doc/a.txt".into()], None, &mut sink).unwrap();
    assert_eq!(sink.got.len(), 2);
}

#[test]
fn iso_reads_joliet_names() {
    let dir = tempfile::tempdir().unwrap();
    let path = make_iso(&dir.path().join("disc.iso"));
    assert_eq!(detect(&path).unwrap(), Some(ArchiveFormat::Iso));
    let index = ArchiveIndex::open(&path).unwrap();
    assert_eq!(names(&index.list("", false, false).unwrap()), ["dir", "readme.txt"]);
    assert_eq!(names(&index.list("dir", false, false).unwrap()), ["Long File Name.txt"]);
    assert_eq!(index.read("dir/Long File Name.txt").unwrap(), b"a long name");
    assert_eq!(index.read("readme.txt").unwrap(), b"read me");
    assert!(index.member("readme.txt").unwrap().modified_ms.is_some());
}

#[test]
fn member_paths_cannot_climb_out() {
    assert_eq!(normalize("../../etc/passwd"), "etc/passwd");
    assert_eq!(normalize("./a//b/./c/"), "a/b/c");
    assert_eq!(normalize("C:\\dir\\..\\file"), "C:/dir/file");
    assert_eq!(single_member_name(Path::new("/x/log.txt.gz")), "log.txt");
}

#[test]
fn flat_lists_take_the_subtree_run() {
    let dir = tempfile::tempdir().unwrap();
    let index = ArchiveIndex::open(&make_zip(dir.path())).unwrap();
    let all: Vec<(String, String)> =
        index.files_in_subtree("", false).into_iter().map(|(e, folder)| (e.name, folder)).collect();
    assert_eq!(all, [("inner.txt".to_string(), "dir".to_string()), ("top.txt".to_string(), String::new())]);
    let hidden: Vec<String> = index.files_in_subtree("dir", true).into_iter().map(|(e, _)| e.name).collect();
    assert_eq!(hidden, [".secret", "inner.txt"]);
    assert_eq!(index.folders_under("dir"), ["dir"]);
}

#[test]
fn shared_indexes_are_kept_until_the_file_changes() {
    let dir = tempfile::tempdir().unwrap();
    let path = make_zip(dir.path());
    let first = shared::index(&path).unwrap();
    let again = shared::index(&path).unwrap();
    assert!(std::sync::Arc::ptr_eq(&first, &again));
    // A changed file is read again.
    std::thread::sleep(std::time::Duration::from_millis(20));
    let mut zip = zip::ZipWriter::new(File::create(&path).unwrap());
    zip.start_file("other.txt", zip::write::SimpleFileOptions::default()).unwrap();
    zip.finish().unwrap();
    let fresh = shared::index(&path).unwrap();
    assert!(!std::sync::Arc::ptr_eq(&first, &fresh));
    assert!(fresh.member("other.txt").is_some());

    let locked = make_7z(&dir.path().join("hidden.7z"), Some("pw"), true);
    assert_eq!(shared::index(&locked).unwrap_err().kind, VfsErrorKind::PasswordRequired);
    assert_eq!(shared::set_password(&locked, "bad").unwrap_err().kind, VfsErrorKind::WrongPassword);
    assert_eq!(shared::password(&locked), None);
    shared::set_password(&locked, "pw").unwrap();
    assert_eq!(shared::password(&locked).as_deref(), Some("pw"));
    assert!(shared::index(&locked).unwrap().member("sub/c.txt").is_some());
}

/// A large zip opens and lists fast; run with `--ignored --nocapture` to
/// see the times.
#[test]
#[ignore]
fn large_archives_open_fast() {
    use std::time::Instant;
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("big.zip");
    let mut zip = zip::ZipWriter::new(File::create(&path).unwrap());
    let opts = zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
    for i in 0..50_000 {
        zip.start_file(format!("d{}/sub{}/file{i}.txt", i % 50, i % 7), opts).unwrap();
        zip.write_all(b"x").unwrap();
    }
    zip.finish().unwrap();
    let tar_path = dir.path().join("big.tar.gz");
    {
        let gz = flate2::write::GzEncoder::new(File::create(&tar_path).unwrap(), flate2::Compression::fast());
        let mut tar = tar::Builder::new(gz);
        for i in 0..50_000 {
            let mut header = tar::Header::new_gnu();
            header.set_size(1);
            header.set_mode(0o644);
            header.set_cksum();
            tar.append_data(&mut header, format!("d{}/file{i}.txt", i % 50), &b"x"[..]).unwrap();
        }
        tar.into_inner().unwrap().finish().unwrap();
    }
    for path in [&path, &tar_path] {
        let start = Instant::now();
        let index = ArchiveIndex::open(path).unwrap();
        let opened = start.elapsed();
        let start = Instant::now();
        let rows = index.list("d7", true, false).unwrap();
        let listed = start.elapsed();
        let start = Instant::now();
        let flat = index.files_in_subtree("", false);
        let walked = start.elapsed();
        println!(
            "{}: {} members, opened in {opened:?}, a folder of {} rows in {listed:?}, flat {} files in {walked:?}",
            path.display(),
            index.len(),
            rows.len(),
            flat.len()
        );
        assert!(opened.as_secs() < 5);
    }
}
