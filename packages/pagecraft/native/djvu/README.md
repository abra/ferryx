# DjVu native backend

This directory supplies Pagecraft's DjVu decoder, built from the vendored
DjVuLibre **3.5.30** sources. The wrapper exposes a narrow C ABI; Dart owns one
worker isolate per document and serializes calls. There is no Rust layer and no
runtime download or dependency on a system-installed DjVuLibre.

## Provenance and license

[UPSTREAM.json](UPSTREAM.json) pins the original release URL and SHA-256. The
`upstream/libdjvu` C++ sources and headers match that release except for the
documented INCL nesting guard below. The upstream
copyright, authors and GPL text are retained beside them. `config.h` is a
Pagecraft-owned modern platform configuration rather than a generated Autoconf
file. `pagecraft_djvu.cpp` is the adapter and uses GPL-2.0-or-later.

DjVuLibre 3.5.30 lacks the later per-thread INCL depth guard. A bundled document
whose internal components include each other can recurse during file creation
before either component is registered, overflowing the stack. Pagecraft carries
the small upstream security fix in
[`patches/0001-limit-incl-nesting-depth.patch`](patches/0001-limit-incl-nesting-depth.patch).
It limits nesting to 32 and unwinds the counter on exceptions. The backport uses
standard C++17 `thread_local` unconditionally: retaining the original optional
`HAVE_GCCTLS` check would silently disable protection in this custom configuration
and on MSVC. `UPSTREAM.json` records original/applied patch hashes and the one
modified file. An original cyclic-bundle fixture verifies typed refusal without
crashing; normal bundled dictionaries remain supported.

**DjVuLibre is GPL-2.0-or-later.** Bundling this backend carries those license
obligations; placing it behind FFI or keeping the application's own MIT notice
does not remove them. Distribution must account for the complete bundled
dependency and corresponding sources. The vendored decoder is built and bundled
by Pagecraft's native build hook, including when another format is imported.

## Build and packaging

`hook/build.dart` uses `native_toolchain_c` alongside the existing MOBI Rust
builder. It compiles release C++17 and registers the native code asset
`src/formats/djvu/native/djvu_native.dart`. Android links libc++ statically, so
no separate `libc++_shared.so` is needed; the builder enables 16 KiB page
alignment. Apple links CoreFoundation for DjVuLibre's file-path conversion.
Native Assets handles platform packaging and loading.
Android/Linux link libm and libdl explicitly, with undefined-symbol link errors
enabled. The hook skips C++ setup when no code assets were requested, as in
Flutter's non-native hook passes.

For an independent host decoder check:

```sh
cmake -S packages/pagecraft/native/djvu -B .local/djvu-native-build \
  -DCMAKE_BUILD_TYPE=Release
cmake --build .local/djvu-native-build --parallel
```

CMake is an optional maintenance path; normal Flutter builds use the Dart hook.
Retest host, Android and Apple targets when changing this configuration. The
current configuration was compiled for macOS arm64, Android arm64/API24,
iOS arm64/device and iOS arm64/simulator. These compilation checks do not claim
runtime validation on every platform. A Windows configuration uses upstream's
Win32 threads, DLL exports and wide file paths; Windows compilation/runtime
remain unverified because this checkout was tested on macOS.

## Contract and limits

The ABI is declared in [pagecraft_djvu.h](pagecraft_djvu.h): open/close,
page metadata, RGBA rendering, text, outline and metadata JSON. Failed calls
return null/zero and leave a borrowed thread-local error. Allocated pixel/string
results must be released with `pagecraft_djvu_free` after Dart has copied them.
No C++ exception may cross the ABI.

Rendering returns opaque RGBA8888 with top-to-bottom rows. Regions use a
top-left origin on the requested full-page size. Text rectangles use top-left
coordinates on the oriented original page, including DjVu's initial rotation.
`text` joins the reported words with single spaces. A page without hidden text
has empty text/words; the backend does not perform OCR.

- Only self-contained single-page and bundled multipage DjVu are accepted.
  Indirect documents and standalone external `INCL`/legacy `NDIR` references
  are rejected before the decoder can resolve sibling files. Bundled dictionaries
  remain internal offset reads; the input is not copied into a full-file buffer.
- Render results are capped at 6 million pixels; intrinsic pages at 100 million
  pixels; document page count at 100,000. Context decoded-data cache is 32 MiB.
  These bounds are not a guarantee about peak native decoder allocations.
- Decoder waits have a bounded per-operation timeout, polled only while work is
  active. DjVuLibre's cancellation is best effort; it cannot guarantee stopping
  a native job instantly after timeout. Calls run outside the UI isolate.
- Text/outline traversal is bounded by node, depth and text/output byte limits.
- IW44, JB2 and MMR decoding are included. Optional JPEG-in-DjVu is disabled:
  those uncommon files report a decoder error. No host libjpeg is assumed.

## Updating the vendor snapshot

Fetch a reviewed official release into ignored local storage, verify the archive
hash, replace the same upstream source/header subset without editing it, and
update `UPSTREAM.json`. Reapply the recorded security patch until the release
contains the same guard, checking its behavior on every configured compiler.
Preserve upstream notices and review security fixes,
configuration changes and licensing. Regenerate no Dart bindings by hand:
the small maintained Dart FFI layer follows the wrapper ABI, not upstream's
large C++ interface. Run format parity, malformed-input, lifecycle and native
packaging tests before changing the release pin.
