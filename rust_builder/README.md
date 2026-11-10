# Rust build integration

This local Flutter FFI plugin builds `rust/crates/ferryx_api` through the
bundled [cargokit](cargokit/README) integration. Flutter's desktop builds
invoke it automatically; application code and the public bridge API belong
in the Rust workspace, not this directory.

From the repository root:

- `make core` builds the host library in `rust/target/debug` for integration
  tests. `make test-dart` runs this first.
- `make build-macos`, `make build-linux` or `make build-windows` builds the
  app and native library on the matching desktop OS.
- After changing the bridge API, `fvm exec make codegen` regenerates Dart
  bindings in `packages/ferryx_backend/lib/src/rust`. The generator version
  must match the bridge dependencies.

Use rustup's current stable toolchain. After a Rust or bridge change, stop
and restart the app completely; Flutter hot reload/restart does not replace
the native library already loaded in the process.

See the [toolchain and commands](../CLAUDE.md#toolchain),
[bridge configuration](../flutter_rust_bridge.yaml) and
[cargokit options](../cargokit_options.yaml). The plugin template also has
Android/iOS scaffolding; Ferryx currently targets macOS, Windows and Linux.
