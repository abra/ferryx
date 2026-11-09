#![forbid(unsafe_code)]

use std::mem::size_of;

use anyhow::{Context, Result, bail, ensure};

pub(crate) enum Decoder {
    PalmDoc,
    Huff(Box<HuffDecoder>),
}

impl Decoder {
    pub(crate) fn load(compression: u16, records: &[Vec<u8>]) -> Result<Self> {
        match compression {
            2 => Ok(Self::PalmDoc),
            17480 => Ok(Self::Huff(Box::new(HuffDecoder::load(records)?))),
            _ => bail!("Unsupported MOBI compression: {compression}"),
        }
    }

    pub(crate) fn decode(&mut self, input: &[u8]) -> Result<Vec<u8>> {
        match self {
            Self::PalmDoc => {
                // Each two-byte back reference can emit at most ten bytes.
                ensure!(
                    input.len() <= MAX_OUTPUT_BYTES / 5,
                    "PalmDOC record exceeds decode budget"
                );
                Ok(decode_palmdoc(input))
            }
            Self::Huff(decoder) => decoder.decode(input, 0),
        }
    }
}

fn decode_palmdoc(input: &[u8]) -> Vec<u8> {
    let mut output = Vec::with_capacity(input.len());
    let mut cursor = 0;
    while let Some(&byte) = input.get(cursor) {
        cursor += 1;
        match byte {
            0 | 9..=127 => output.push(byte),
            1..=8 => {
                let end = (cursor + usize::from(byte)).min(input.len());
                output.extend_from_slice(&input[cursor..end]);
                cursor = end;
            }
            128..=191 => {
                let Some(&next) = input.get(cursor) else {
                    break;
                };
                cursor += 1;
                let pair = (usize::from(byte) << 8) | usize::from(next);
                let distance = (pair & 0x3fff) >> 3;
                for _ in 0..(pair & 7) + 3 {
                    // Preserve Dart's zero fill for absent/zero-distance references.
                    let value = output
                        .len()
                        .checked_sub(distance)
                        .and_then(|index| output.get(index))
                        .copied()
                        .unwrap_or(0);
                    output.push(value);
                }
            }
            192..=255 => output.extend_from_slice(&[b' ', byte ^ 0x80]),
        }
    }
    output
}

#[derive(Clone, Copy, Default)]
struct Prefix {
    found: bool,
    length: usize,
    value: u32,
}

#[derive(Clone, Copy, Default)]
struct CodeRange {
    min: u32,
    max: u32,
}

#[derive(Clone, Copy, PartialEq)]
enum EntryState {
    Packed,
    Expanding,
    Decoded,
}

struct Entry {
    bytes: Vec<u8>,
    state: EntryState,
}

// Bound recursive dictionaries and decoded records from malformed files.
const MAX_OUTPUT_BYTES: usize = 64 * 1024 * 1024;
const MAX_CACHE_BYTES: usize = 64 * 1024 * 1024;
const MAX_DEPTH: usize = 128;

pub(crate) struct HuffDecoder {
    prefixes: [Prefix; 256],
    ranges: [CodeRange; 33],
    dictionary: Vec<Entry>,
    // Entry metadata and all retained payloads, including buffers moved out
    // temporarily while expanding. Recursive output shares the same budget.
    dictionary_bytes: usize,
    expanding_bytes: usize,
}

impl HuffDecoder {
    fn load(records: &[Vec<u8>]) -> Result<Self> {
        let huff = records.first().context("Missing HUFF dictionary record")?;
        ensure!(huff.starts_with(b"HUFF"), "Invalid HUFF record");
        let offset1 = read_u32(huff, 8)? as usize;
        let offset2 = read_u32(huff, 12)? as usize;
        let prefix_bytes = read_slice(huff, offset1, 256 * 4)?;
        let range_bytes = read_slice(huff, offset2, 32 * 8)?;
        let mut prefixes = [Prefix::default(); 256];
        for (i, entry) in prefixes.iter_mut().enumerate() {
            let word = read_u32(prefix_bytes, i * 4)?;
            let length = (word & 0x1f) as usize;
            *entry = Prefix {
                found: word & 0x80 != 0,
                length,
                value: word >> 8,
            };
        }
        let mut ranges = [CodeRange::default(); 33];
        for (i, range) in ranges.iter_mut().skip(1).enumerate() {
            *range = CodeRange {
                min: read_u32(range_bytes, i * 8)?,
                max: read_u32(range_bytes, i * 8 + 4)?,
            };
        }
        let mut dictionary = Vec::new();
        let mut dictionary_bytes = 0usize;
        for record in &records[1..] {
            ensure!(record.starts_with(b"CDIC"), "Invalid CDIC record");
            let header_length = read_u32(record, 4)? as usize;
            let total = read_u32(record, 8)? as usize;
            let code_length = read_u32(record, 12)?;
            let capacity = 1usize
                .checked_shl(code_length)
                .context("Invalid CDIC code length")?;
            let remaining = total
                .checked_sub(dictionary.len())
                .context("Invalid CDIC entry count")?;
            let count = capacity.min(remaining);
            let buffer = record
                .get(header_length..)
                .context("Invalid CDIC header length")?;
            ensure!(count <= buffer.len() / 2, "Truncated CDIC offset table");
            ensure!(
                count <= (MAX_CACHE_BYTES - dictionary_bytes) / size_of::<Entry>(),
                "HUFF dictionary cache limit exceeded"
            );
            dictionary_bytes += count * size_of::<Entry>();
            dictionary
                .try_reserve_exact(count)
                .context("Cannot allocate HUFF dictionary entries")?;
            for i in 0..count {
                let offset = usize::from(read_u16(buffer, i * 2)?);
                let word = read_u16(buffer, offset)?;
                let length = usize::from(word & 0x7fff);
                let source = buffer
                    .get(offset + 2..offset + 2 + length)
                    .context("Truncated CDIC dictionary entry")?;
                ensure!(
                    length <= MAX_CACHE_BYTES - dictionary_bytes,
                    "HUFF dictionary cache limit exceeded"
                );
                let mut bytes = Vec::new();
                bytes
                    .try_reserve_exact(length)
                    .context("Cannot allocate HUFF dictionary entry")?;
                bytes.extend_from_slice(source);
                dictionary_bytes += length;
                let state = if word & 0x8000 != 0 {
                    EntryState::Decoded
                } else {
                    EntryState::Packed
                };
                dictionary.push(Entry { bytes, state });
            }
        }
        Ok(Self {
            prefixes,
            ranges,
            dictionary,
            dictionary_bytes,
            expanding_bytes: 0,
        })
    }

    fn decode(&mut self, input: &[u8], depth: usize) -> Result<Vec<u8>> {
        ensure!(depth <= MAX_DEPTH, "HUFF dictionary nesting limit exceeded");
        let mut output = Vec::new();
        match self.decode_into(input, depth, &mut output) {
            Ok(()) => Ok(output),
            Err(error) => {
                if depth > 0 {
                    self.expanding_bytes -= output.len();
                }
                Err(error)
            }
        }
    }

    fn decode_into(&mut self, input: &[u8], depth: usize, output: &mut Vec<u8>) -> Result<()> {
        let bit_length = input.len().checked_mul(8).context("HUFF input too large")?;
        let mut cursor = 0;
        while cursor < bit_length {
            let bits = read_bits(input, cursor);
            let prefix = self.prefixes[(bits >> 24) as usize];
            let mut length = prefix.length;
            let mut value = prefix.value;
            ensure!(length > 0, "Zero-length HUFF prefix");
            if !prefix.found {
                loop {
                    ensure!(length <= 32, "Invalid HUFF code length");
                    if bits >> (32 - length) >= self.ranges[length].min {
                        break;
                    }
                    length += 1;
                }
                value = self.ranges[length].max;
            }
            cursor += length;
            if cursor > bit_length {
                break;
            }
            let code = value
                .checked_sub(bits >> (32 - length))
                .context("Huffman code outside the dictionary")? as usize;
            ensure!(
                code < self.dictionary.len(),
                "Huffman code outside the dictionary"
            );
            self.expand(code, depth)?;
            let length = self.dictionary[code].bytes.len();
            ensure!(
                length <= MAX_OUTPUT_BYTES - output.len(),
                "HUFF output limit exceeded"
            );
            if depth > 0 {
                ensure!(
                    length <= MAX_CACHE_BYTES - self.dictionary_bytes - self.expanding_bytes,
                    "HUFF dictionary cache limit exceeded"
                );
            }
            output
                .try_reserve(length)
                .context("Cannot allocate HUFF output")?;
            if depth > 0 {
                self.expanding_bytes += length;
            }
            output.extend_from_slice(&self.dictionary[code].bytes);
        }
        Ok(())
    }

    fn expand(&mut self, code: usize, depth: usize) -> Result<()> {
        match self.dictionary[code].state {
            EntryState::Decoded => return Ok(()),
            EntryState::Expanding => bail!("Cyclic HUFF dictionary"),
            EntryState::Packed => {}
        }
        self.dictionary[code].state = EntryState::Expanding;
        let packed = std::mem::take(&mut self.dictionary[code].bytes);
        let decoded = self.decode(&packed, depth + 1);
        match decoded {
            Ok(bytes) => {
                self.expanding_bytes -= bytes.len();
                self.dictionary_bytes = self.dictionary_bytes - packed.len() + bytes.len();
                self.dictionary[code] = Entry {
                    bytes,
                    state: EntryState::Decoded,
                };
                Ok(())
            }
            Err(error) => {
                self.dictionary[code] = Entry {
                    bytes: packed,
                    state: EntryState::Packed,
                };
                Err(error)
            }
        }
    }
}

fn read_u16(bytes: &[u8], offset: usize) -> Result<u16> {
    let slice = read_slice(bytes, offset, 2)?;
    Ok(u16::from_be_bytes([slice[0], slice[1]]))
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32> {
    let slice = read_slice(bytes, offset, 4)?;
    Ok(u32::from_be_bytes([slice[0], slice[1], slice[2], slice[3]]))
}

fn read_slice(bytes: &[u8], offset: usize, length: usize) -> Result<&[u8]> {
    let end = offset
        .checked_add(length)
        .context("Dictionary offset overflow")?;
    bytes.get(offset..end).context("Truncated dictionary bytes")
}

fn read_bits(bytes: &[u8], from: usize) -> u32 {
    let mut bits = 0u64;
    for offset in 0..5 {
        bits = (bits << 8) | u64::from(bytes.get((from >> 3) + offset).copied().unwrap_or(0));
    }
    (bits >> (8 - (from & 7))) as u32
}

#[cfg(test)]
#[path = "decoder/tests.rs"]
mod tests;
