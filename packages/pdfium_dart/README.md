# pdfium_dart

## Ferryx local copy

Based on the MIT-licensed [pdfium_dart 0.2.5](https://pub.dev/packages/pdfium_dart/versions/0.2.5)
from [pdfrx](https://github.com/espresso3389/pdfrx/tree/master/packages/pdfium_dart).
Runtime bindings, library loading and link-hook behavior are unchanged.
The build hook still bundles **PDFium Chromium 7811**.

The local build hook adds bounded retries and timeouts, an official GitHub
release-asset API fallback, and archive size/SHA-256 verification against
`hook/pdfium_binaries.json`. Only the requested library is extracted. Archive
cache and build output writes are atomic; failed downloads never publish a
partial library. The HTTP client honors proxy environment variables.

Verified archives are cached by digest outside the build directory:

- macOS: `~/Library/Caches/pdfium_dart`
- Linux: `$XDG_CACHE_HOME/pdfium_dart` or `~/.cache/pdfium_dart`
- Windows: `%LOCALAPPDATA%/pdfium_dart`

Set `PDFIUM_DART_CACHE` to override this directory (for example, a restored CI
cache). A cache populated for every target architecture allows the PDFium hook
to run offline after `flutter clean`; other native dependencies may still need
the network. macOS release builds need both ARM64 and x64 archives. Corrupt
cache entries are ignored and replaced. Download failures report HTTP status
and endpoint. Both download routes use GitHub; an empty cache still requires
network access to at least one of them.

The app, Pagecraft and viewer pubspecs each override `pdfium_dart` to this copy:
Dart does not inherit dependency overrides from dependencies. Keep these in
sync. `make get`, `make analyze` and `make test-dart` include this pure Dart
package. For focused checks:

```sh
cd packages/pdfium_dart
fvm dart pub get
fvm dart analyze
fvm dart test
```

To update PDFium, review the upstream bindings/runtime and `pdfium_flutter`
compatibility together. Refresh the release tag, asset URLs, API IDs, sizes and
SHA-256 digests from the [official release API](https://api.github.com/repos/bblanchon/pdfium-binaries/releases/tags/chromium%2F7811),
then verify downloads and run native tests and release builds. Do not update
just the binary tag without reviewing the corresponding generated bindings.

## Upstream documentation

Dart FFI bindings for the PDFium library. This package provides low-level access to PDFium's C API from Dart.

This package is part of the [pdfrx](https://github.com/espresso3389/pdfrx) project.

## Overview

This package contains auto-generated FFI bindings for PDFium using [ffigen](https://pub.dev/packages/ffigen). It is designed to be a minimal, pure Dart package that other packages can depend on to access PDFium functionality.

**Key Features:**

- Pure Dart package with no Flutter dependencies
- Auto-generated FFI bindings using [ffigen](https://pub.dev/packages/ffigen)
- Provides direct access to PDFium's C API
- Downloads and bundles PDFium at build time using Dart native assets
- Includes [getPdfium()](https://pub.dev/documentation/pdfium_dart/latest/pdfium_dart/getPdfium.html) for resolving PDFium across Dart and Flutter runtimes
- Supports Windows, Linux, Android, and macOS build hooks

## Usage

### Basic Usage

This package is primarily intended to be used as a dependency by higher-level packages like [pdfium_flutter](https://pub.dev/packages/pdfium_flutter) and [pdfrx_engine](https://pub.dev/packages/pdfrx_engine). Direct usage is possible but not recommended unless you need low-level PDFium access.

```dart
import 'package:pdfium_dart/pdfium_dart.dart';
import 'dart:ffi';

// If you already have PDFium loaded
final pdfium = PDFium(DynamicLibrary.open('/path/to/libpdfium.so'));
```

### PDFium Loading

The [getPdfium](https://pub.dev/documentation/pdfium_dart/latest/pdfium_dart/getPdfium.html) function resolves the PDFium library for the current runtime. You can also pass an explicit module path for custom deployments or tests:

```dart
import 'package:pdfium_dart/pdfium_dart.dart';

void main() async {
  // Resolves PDFium for the current Dart or Flutter runtime.
  final pdfium = getPdfium();

  // Or load a specific shared library.
  final customPdfium = getPdfium(modulePath: '/path/to/libpdfium.so');

  // Use PDFium API
  // ...
}
```

The build hook downloads binaries from [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries/releases) and exposes them through Dart native assets. At runtime, `getPdfium()` chooses the appropriate loading strategy:

- `modulePath` is used first when explicitly provided.
- Flutter apps on iOS/macOS use the PDFium XCFramework that is already linked into the app by `pdfium_flutter`.
- Native PDFium assets are not built for iOS; Flutter iOS apps should depend on `pdfium_flutter` so the XCFramework is linked by the Flutter plugin.
- Pure Dart commands on macOS, such as `dart test`, `dart run`, and `dart compile`, use the `libpdfium.dylib` native asset.
- Flutter apps on Linux look for `libpdfium.so` in the shared library directory relative to the resolved executable.
- Other supported platforms first try the platform library name, then fall back to the bundled native asset recorded in `.dart_tool/native_assets.yaml`.

## Generating Bindings

### Prerequisites

The [ffigen](https://pub.dev/packages/ffigen) process requires LLVM/Clang to be installed for parsing C headers:

- **macOS**: Install via Homebrew

  ```bash
  brew install llvm
  ```

- **Linux**: Install via package manager

  ```bash
  # Ubuntu/Debian
  sudo apt-get install libclang-dev

  # Fedora
  sudo dnf install clang-devel
  ```

- **Windows**: Download and install LLVM from [llvm.org](https://releases.llvm.org/)

### Regenerating Bindings

To regenerate the FFI bindings:

1. Run the ffigen helper:

   ```bash
   dart tool/ffigen.dart
   ```

   The helper downloads PDFium headers into `.dart_tool/pdfium_headers/` before running `ffigen`.

   Use `dart tool/ffigen.dart --force` to refresh the downloaded headers, or
   `dart tool/ffigen.dart --download-only` to only prepare the headers.

The bindings are generated from PDFium headers using the `ffigen` configuration in `pubspec.yaml`.

## Platform Support

| Platform | Architecture | Support |
|----------|-------------|---------|
| Windows  | x64, ARM64, x86 | ✅  |
| Linux    | x64, ARM64, ARM, x86 | ✅ |
| Android  | ARM64, ARMv7, x86, x86_64 | ✅ |
| macOS    | x64, ARM64  | ✅      |

**Note:** For Flutter applications, use [pdfium_flutter](https://pub.dev/packages/pdfium_flutter) unless you specifically need the lower-level Dart bindings directly. `pdfium_flutter` includes the Flutter deployment layer for all native platforms except Web.
