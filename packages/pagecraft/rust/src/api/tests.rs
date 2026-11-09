use super::*;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT_FILE: AtomicUsize = AtomicUsize::new(0);

struct Fixture(PathBuf);

impl Fixture {
    fn new(bytes: &[u8]) -> Self {
        let path = std::env::temp_dir().join(format!(
            "pagecraft-mobi-{}-{}",
            std::process::id(),
            NEXT_FILE.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::write(&path, bytes).unwrap();
        Self(path)
    }

    fn open(&self, config: MobiTextConfig) -> Result<MobiTextReader> {
        MobiTextReader::open(self.0.to_str().unwrap().to_owned(), config)
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        std::fs::remove_file(&self.0).unwrap();
    }
}

fn config(offsets: &[i64], compression: u16) -> MobiTextConfig {
    MobiTextConfig {
        record_offsets: offsets.to_vec(),
        text_start: 0,
        text_count: (offsets.len() - 1) as u32,
        dictionary_start: 0,
        dictionary_count: 0,
        compression,
        trailing_flags: 0,
    }
}

#[test]
fn records_are_read_by_offset_in_requested_order() -> Result<()> {
    let fixture = Fixture::new(b"headeronetwothree");
    let mut settings = config(&[0, 6, 9, 12, 17], 1);
    settings.text_start = 1;
    settings.text_count = 3;
    let mut reader = fixture.open(settings)?;
    assert_eq!(reader.read_record(2)?, b"three");
    assert_eq!(reader.read_record(0)?, b"one");
    assert_eq!(reader.read_records(1, 2)?, b"twothree");
    assert_eq!(reader.read_records(3, 0)?, b"");
    Ok(())
}

#[test]
fn palmdoc_decoding_strips_trailing_bytes_before_decoding() -> Result<()> {
    let fixture = Fixture::new(&[b'a', 0xc2, 0x81]);
    let mut settings = config(&[0, 3], 2);
    settings.trailing_flags = 2;
    let mut reader = fixture.open(settings)?;
    assert_eq!(reader.read_record(0)?, b"a B");
    Ok(())
}

#[test]
fn trailing_entries_match_dart_clamping_and_zero_size() {
    assert_eq!(strip_trailing(&[1, 2, 0x80], 2), &[1, 2, 0x80]);
    assert_eq!(strip_trailing(&[1, 2, 0x83], 2), &[]);
    assert_eq!(strip_trailing(&[1, 2, 0], 1), &[1, 2]);
    assert_eq!(strip_trailing(&[], 3), &[]);
    assert_eq!(strip_trailing(&[1, 2, 0x81, 0x81], 6), &[1, 2]);
}

#[test]
fn invalid_offsets_and_configurations_return_errors() {
    let fixture = Fixture::new(b"abc");
    for offsets in [&[0, 4][..], &[0, 2][..], &[-1, 3][..], &[2, 1, 3][..]] {
        assert!(fixture.open(config(offsets, 1)).is_err());
    }
    assert!(fixture.open(config(&[0, 3], 99)).is_err());
    let mut settings = config(&[0, 3], 1);
    settings.text_count = 2;
    assert!(fixture.open(settings).is_err());
    assert!(fixture.open(config(&[0, 3], 17480)).is_err());
}

#[test]
fn invalid_reads_do_not_poison_the_session_and_close_is_idempotent() -> Result<()> {
    let fixture = Fixture::new(b"abc");
    let mut reader = fixture.open(config(&[0, 3], 1))?;
    assert!(reader.read_record(1).is_err());
    assert!(reader.read_records(u32::MAX, 1).is_err());
    assert!(reader.read_records(0, u32::MAX).is_err());
    assert_eq!(reader.read_record(0)?, b"abc");
    reader.close();
    reader.close();
    assert!(reader.read_record(0).is_err());
    assert!(reader.read_records(0, 0).is_err());
    Ok(())
}

#[test]
fn oversized_sparse_record_is_rejected_before_allocation() -> Result<()> {
    let fixture = Fixture::new(&[]);
    let length = MAX_RECORD_BYTES as u64 + 1;
    File::options()
        .write(true)
        .open(&fixture.0)?
        .set_len(length)?;
    let mut reader = fixture.open(config(&[0, length as i64], 1))?;
    assert!(reader.read_record(0).is_err());
    Ok(())
}

#[test]
fn huff_dictionary_is_read_from_the_file_and_cached_for_later_records() -> Result<()> {
    fn u32_at(bytes: &mut [u8], offset: usize, value: u32) {
        bytes[offset..offset + 4].copy_from_slice(&value.to_be_bytes());
    }
    let mut huff = vec![0; 24 + 256 * 4 + 32 * 8];
    huff[..4].copy_from_slice(b"HUFF");
    u32_at(&mut huff, 8, 24);
    u32_at(&mut huff, 12, 24 + 256 * 4);
    for index in 0..256 {
        u32_at(&mut huff, 24 + index * 4, (255 << 8) | 0x80 | 8);
    }
    let mut cdic = vec![0; 20];
    cdic[..4].copy_from_slice(b"CDIC");
    u32_at(&mut cdic, 4, 16);
    u32_at(&mut cdic, 8, 2);
    u32_at(&mut cdic, 12, 8);
    cdic[16..20].copy_from_slice(&[0, 4, 0, 8]);
    cdic.extend_from_slice(&[0, 2, 254, 254, 0x80, 5]);
    cdic.extend_from_slice(b"word ");
    let mut bytes = huff.clone();
    bytes.extend_from_slice(&cdic);
    bytes.extend_from_slice(&[255, 254]);
    let offsets = [
        0,
        huff.len() as i64,
        (huff.len() + cdic.len()) as i64,
        bytes.len() as i64,
    ];
    let fixture = Fixture::new(&bytes);
    let mut settings = config(&offsets, 17480);
    settings.text_start = 2;
    settings.text_count = 1;
    settings.dictionary_count = 2;
    let mut reader = fixture.open(settings)?;
    assert_eq!(reader.read_record(0)?, b"word word word ");
    assert_eq!(reader.read_records(0, 1)?, b"word word word ");
    Ok(())
}
