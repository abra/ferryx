# lzma-rust2 0.16.5, patched for Ferryx

The crate as published (Apache-2.0, see `LICENSE`), its `src/` and manifest
only, with two changes, each marked `Ferryx:`.

1. In `src/lzma_reader.rs` and `src/lzma2_reader.rs`: a turn of the decode
   loop that copies no byte and has not reached the end returns a
   "corrupted input data" error.
2. In `src/lzma2_reader_mt.rs`: a work unit (the chunks from one
   independent chunk to the next) that grows past 128 MiB unpacked stops
   being gathered; it and the rest of the stream are decoded on the
   caller's thread through a plain `Lzma2Reader` (so with change 1), once
   the units sent before it are returned. A unit's output is allocated
   once at its unpacked size, which the chunk headers give. And two fixes
   of 0.23 brought back: the reader reads ahead while fewer units are
   queued than there are workers (0.16.5 waited for a result as soon as
   one unit was queued, so one worker decoded at a time), and input with
   no chunk at all ends instead of waiting for a unit never sent.

Without the first, a 7z archive decoded with a wrong password (AES gives random
bytes) could leave `Lzma2Reader::read` or `LzmaReader::read` spinning
forever: about one wrong password in ten in `ferryx_vfs`'s
`archive::tests::seven_zip_passwords`. 0.23.0 has the same loop. The
multithreaded reader's workers decode through `Lzma2Reader` too, so they
end on such input as well (`archive::tests::seven_zip_lzma2_in_parts_and_in_one_stream`).

Without the second, a stream written on one thread (one independent chunk
at its start) was read into memory whole, and decoded into memory whole,
before its first byte came out: a 7z block of gigabytes in RAM.

Wired in through `[patch.crates-io]` in `rust/Cargo.toml`; remove both once
a published release has a progress check and a bounded multithreaded
reader.
