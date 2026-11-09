#![forbid(unsafe_code)]

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};

use anyhow::{Context, Result, ensure};
use flutter_rust_bridge::frb;

use crate::decoder::Decoder;

const MAX_RECORD_BYTES: usize = 64 * 1024 * 1024;
const MAX_BATCH_BYTES: usize = 256 * 1024 * 1024;

/// Dart parses PDB/MOBI headers; Rust owns only text record I/O and decoding.
pub struct MobiTextConfig {
    pub record_offsets: Vec<i64>,
    pub text_start: u32,
    pub text_count: u32,
    pub dictionary_start: u32,
    pub dictionary_count: u32,
    pub compression: u16,
    pub trailing_flags: u32,
}

#[frb(opaque)]
pub struct MobiTextReader {
    source: Option<Source>,
}

struct Source {
    file: File,
    offsets: Vec<u64>,
    text_start: usize,
    text_count: usize,
    decoder: Option<Decoder>,
    trailing_flags: u32,
}

impl MobiTextReader {
    pub fn open(path: String, config: MobiTextConfig) -> Result<Self> {
        let file = File::open(path)?;
        let length = file.metadata()?.len();
        ensure!(
            config.record_offsets.len() >= 2,
            "Missing PDB record offsets"
        );
        let offsets = config
            .record_offsets
            .into_iter()
            .map(u64::try_from)
            .collect::<std::result::Result<Vec<_>, _>>()?;
        ensure!(offsets.last() == Some(&length), "PDB file size changed");
        ensure!(
            offsets.windows(2).all(|pair| pair[0] <= pair[1]),
            "Invalid PDB record offsets"
        );
        let records = offsets.len() - 1;
        let text_start = config.text_start as usize;
        let text_count = config.text_count as usize;
        ensure!(
            text_start <= records && text_count <= records - text_start,
            "Invalid MOBI text record range"
        );
        let mut source = Source {
            file,
            offsets,
            text_start,
            text_count,
            decoder: None,
            trailing_flags: config.trailing_flags,
        };
        if config.compression != 1 {
            let dictionary = if config.compression == 17480 {
                let start = config.dictionary_start as usize;
                let count = config.dictionary_count as usize;
                ensure!(
                    start <= records && count <= records - start,
                    "Invalid HUFF dictionary range"
                );
                let mut dictionary = Vec::with_capacity(count);
                let mut total = 0;
                for index in start..start + count {
                    let record = source.read_raw(index)?;
                    ensure!(
                        record.len() <= MAX_RECORD_BYTES - total,
                        "HUFF dictionary exceeds 64 MiB"
                    );
                    total += record.len();
                    dictionary.push(record);
                }
                dictionary
            } else {
                Vec::new()
            };
            source.decoder = Some(Decoder::load(config.compression, &dictionary)?);
        }
        Ok(Self {
            source: Some(source),
        })
    }

    /// FRB dispatches file I/O and decoding onto its worker pool.
    pub fn read_record(&mut self, index: u32) -> Result<Vec<u8>> {
        self.source
            .as_mut()
            .context("MOBI text reader is closed")?
            .read_text(index as usize)
    }

    /// A MOBI 6 stream can be requested without one bridge call per record.
    /// KF8 callers continue to request just the records their range needs.
    pub fn read_records(&mut self, start: u32, count: u32) -> Result<Vec<u8>> {
        let source = self.source.as_mut().context("MOBI text reader is closed")?;
        let start = start as usize;
        let count = count as usize;
        ensure!(
            start <= source.text_count && count <= source.text_count - start,
            "Invalid MOBI text batch range"
        );
        let mut output = Vec::new();
        for index in start..start + count {
            let record = source.read_text(index)?;
            ensure!(
                record.len() <= MAX_BATCH_BYTES - output.len(),
                "MOBI text batch exceeds 256 MiB"
            );
            output.extend_from_slice(&record);
        }
        Ok(output)
    }

    /// Release the file and dictionary before the opaque handle is disposed.
    pub fn close(&mut self) {
        self.source = None;
    }
}

impl Source {
    fn read_raw(&mut self, index: usize) -> Result<Vec<u8>> {
        let start = self.offsets[index];
        let length = usize::try_from(self.offsets[index + 1] - start)?;
        ensure!(length <= MAX_RECORD_BYTES, "MOBI record exceeds 64 MiB");
        let mut bytes = vec![0; length];
        self.file.seek(SeekFrom::Start(start))?;
        self.file.read_exact(&mut bytes)?;
        Ok(bytes)
    }

    fn read_text(&mut self, index: usize) -> Result<Vec<u8>> {
        ensure!(
            index < self.text_count,
            "MOBI text record index out of range"
        );
        let bytes = self.read_raw(self.text_start + index)?;
        let text = strip_trailing(&bytes, self.trailing_flags);
        match &mut self.decoder {
            Some(decoder) => decoder.decode(text),
            None => Ok(text.to_vec()),
        }
    }
}

fn strip_trailing(mut bytes: &[u8], flags: u32) -> &[u8] {
    for _ in 0..(flags >> 1).count_ones() {
        let mut length = 0usize;
        for &byte in &bytes[bytes.len().saturating_sub(4)..] {
            if byte & 0x80 != 0 {
                length = 0;
            }
            length = (length << 7) | usize::from(byte & 0x7f);
        }
        bytes = &bytes[..bytes.len().saturating_sub(length)];
    }
    if flags & 1 != 0
        && let Some(last) = bytes.last()
    {
        bytes = &bytes[..bytes.len().saturating_sub(usize::from(last & 3) + 1)];
    }
    bytes
}

#[frb(sync)]
pub fn is_release_build() -> bool {
    !cfg!(debug_assertions)
}

#[cfg(test)]
mod tests;
