# lzma-rust2 0.16.5, patched for Ferryx

The crate as published (Apache-2.0, see `LICENSE`), its `src/` and manifest
only, with one change in `src/lzma_reader.rs` and `src/lzma2_reader.rs`
(marked `Ferryx:`): a turn of the decode loop that copies no byte and has
not reached the end returns a "corrupted input data" error.

Without it, a 7z archive decoded with a wrong password (AES gives random
bytes) could leave `Lzma2Reader::read` or `LzmaReader::read` spinning
forever: about one wrong password in ten in `ferryx_vfs`'s
`archive::tests::seven_zip_passwords`. 0.23.0 has the same loop.

Wired in through `[patch.crates-io]` in `rust/Cargo.toml`; remove both once
a published release has a progress check.
