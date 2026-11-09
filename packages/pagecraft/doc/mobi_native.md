# Native MOBI/KF8 backend

Pagecraft's internal native MOBI/KF8 text-record backend owns file reads by record
offset, trailing-entry removal, PalmDOC/HUFF-CDIC decompression and a per-book
dictionary cache. PDB/MOBI headers, combined-file selection, metadata,
resources, chapter reconstruction and rendering remain in Dart.

This backend belongs to the `pagecraft` Dart package. The Rust crate and native
library keep the name `pagecraft_mobi_native`; there is no separate Dart package
or public native-reader API. The Dart wrapper and loader live under
`lib/src/formats/mobi/native/`, generated Dart bindings under its `rust/`
subdirectory, and the Rust crate under `rust/`. Paths in this document are
relative to `packages/pagecraft/` unless stated otherwise.

The internal `NativeMobiTextReader.open` accepts the header-derived record offsets
and text and dictionary ranges. `readRecord` reads one text record; `readRecords`
returns a contiguous batch. MOBI 6 requests its full text in one bridge call; KF8
continues loading individual records as needed. The reader does not preload the
file or cache decoded text. Pagecraft retains its existing KF8 range caches.

## Ownership and errors

All file I/O and decoding use asynchronous FRB calls to its worker pool. Reads
on one reader are serialized. `close` stops accepting new reads, drains accepted
reads, releases the file/dictionary and disposes the opaque handle once. Call it
even after a failed read. Failed construction releases its resources through
Rust ownership. Each Dart isolate initializes one bridge lazily.

Native file/decoding failures become the internal `MobiNativeException`; Pagecraft
translates them to `PagecraftException`. The production path does not silently retry
decoding with another backend. Invalid indices are `RangeError`; reads after
close are `StateError`.

Budgets bound damaged input: 64 MiB per stored record, 64 MiB of dictionary
input, one 64 MiB dictionary budget shared by packed/decoded entry payloads,
entry metadata and in-progress recursive output, 64 MiB decoded HUFF text and
256 MiB per batch. The dictionary budget is checked before copying entries
and as recursive output grows; repeated CDIC offsets cannot bypass it. These
byte budgets do not include allocator bookkeeping or spare vector capacity.
PalmDOC limits
packed input to one fifth of the decoded budget, its worst-case expansion.
Recursive HUFF expansion is limited to 128 levels; cycles are errors. Normal
MOBI text records are usually 4 KiB. A book exceeding a budget reports an error.

## Building

Use the project's FVM SDK and install Rust through rustup. The exact compiler
and platform targets are declared in `rust/rust-toolchain.toml` (1.99.0).
Flutter/Dart invokes Pagecraft's `hook/build.dart`, which uses FRB's
[Native Assets backend](https://cjycode.com/flutter_rust_bridge/manual/integrate/native-assets)
to build Cargo in release mode with `--locked` and bundle the platform library.
No prebuilt library, local library-path environment variable or manual copying
step is required. The hook resolves the pinned compiler through rustup so a
Homebrew compiler earlier in PATH cannot select the wrong target libraries.

From the repository root:

```sh
cd packages/pagecraft/rust
rustup toolchain install 1.99.0 --profile minimal
rustup show active-toolchain
cd ../../..
make get
```

The first build may download the pinned compiler, standard libraries and Cargo
dependencies. Android requires its SDK/NDK and iOS requires Xcode. Android,
iOS/device/simulator, macOS, Linux and Windows targets are declared. Web is not
supported. Supported-target declarations are not evidence of device testing;
record the platforms actually checked in change reports. Rust and PDFium native
assets are built/bundled even when a consumer imports another Pagecraft format.

FRB's normal loader handles packaged Flutter libraries. Host Flutter tests and
Dart CLI runs resolve Pagecraft's asset ID from the generated native-assets
manifest; AOT CLI bundles use their bundled `lib/` directory. This adaptation
is isolated in `lib/src/formats/mobi/native/native_library.dart`.

The Dart runtime, Rust runtime, build-hook adapter and generator are pinned to
`flutter_rust_bridge` **2.13.0**. Generated bindings are checked in. Pagecraft's
`flutter_rust_bridge.yaml` owns their paths. After changing Rust API signatures,
regenerate from the repository root:

```sh
make generate-pagecraft-mobi-native
make analyze-pagecraft-mobi-rust
make test-pagecraft-mobi-rust
```

Clean the consuming app's build output after renaming native libraries:
incremental Xcode builds can retain frameworks from the previous name.

## Validation and performance

`make analyze` includes Rust formatting/Clippy and Dart analysis. `make test`
includes Rust unit tests and Pagecraft's Dart tests through the real build
hook. Pagecraft's MOBI suite covers full books, KF8 lazy reads, native/Dart parity,
close races and damaged initialization. The native tests cover concurrency,
closed readers, bad ranges, PalmDOC, HUFF/CDIC and bounded malformed input.

Device packaging and book opening are checked from the repository root with
the existing app runner:

```sh
fvm flutter test integration_test/mobi_native_test.dart -d <device-id>
```

No benchmark package is a runtime dependency. The earlier decoder prototype
remains in `benchmarks/mobi_rust`; the runtime reader comparison in
`benchmarks/reader_native` uses the production container for MOBI and forces
its Dart reference explicitly. These paths are relative to the repository root.
File I/O, bridge dispatch and returned bytes belong in timed operations; report
library startup and peak RSS separately. Host text-stream speedups do not
establish total book-open speed or device FPS.
