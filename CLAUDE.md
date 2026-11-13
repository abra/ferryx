# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Documentation layout

- Keep user-facing information in one `README.md`, with a table of contents
  and collapsible details for longer references. Do not split it into
  separate guides unless the user explicitly asks.
- Keep setup, build and maintenance instructions here and internal design in
  `ARCHITECTURE.md`. README is for application users, not development setup.
- Update the relevant README section with behavior changes.

## Toolchain

- Flutter is pinned in `.fvmrc`; always use `fvm flutter` / `fvm dart`
  (every Make target does, except `make codegen`: `flutter_rust_bridge_codegen`
  calls Flutter/Dart on PATH; use `fvm exec make codegen` to supply the
  project's pinned SDK).
- Flutter 3.50 uses the standalone `material_ui` / `cupertino_ui` packages.
  Use their imports and `FerryxSupportedLocales.delegates` for UI localization;
  `gen-l10n` still emits SDK delegates in its generated convenience list.
  Markdown and HTML renderers retain a scoped compatibility bridge until
  those dependencies migrate. Keep that boundary covered by preview tests.
- After changing the Flutter pin, stop the old `flutter run` session, run
  `fvm flutter clean` and `make get`, then rebuild. Xcode's precompiled
  FlutterMacOS modules must not survive a change of SDK headers.
- Rust builds inside the Flutter build go through cargokit, which runs
  `rustup run stable cargo`. Keep the rustup toolchain current
  (`rustup update stable`). `macos/Podfile` pins `RUSTC` for every Cargokit
  script phase, including third-party plugins; the local
  `rust_builder/cargokit/build_pod.sh` also pins it. A Homebrew Rust ahead
  on PATH must not select a different std or miss rustup's Intel target.
  The Makefile calls `cargo` from PATH; keep it on that same toolchain.
  The workspace's declared `rust-version = "1.85"` is below the current
  lockfile's requirements: the RAR dependencies require at least 1.97.1.
  CI uses stable and does not verify the declared minimum.
- The local reader engine lives in `packages/pagecraft`, with its local
  `native_text_selection` dependency beside it. Its separate Rust crate
  pins its toolchain in `packages/pagecraft/rust/rust-toolchain.toml`;
  the Makefile and native build hook select that compiler explicitly.
  Keep its Dart and Cargo lockfiles; edit the local sources, not Pub's cache.
- `packages/irondash_engine_context` is a local copy of 0.5.5. Its macOS
  patch defers publishing an engine handle until queued view registration
  finishes and returns nil for stale handles. Keep the root path override;
  otherwise startup can crash in drag/drop before the window appears.
- `packages/pdfium_dart` is a local MIT-licensed copy of 0.2.5. Its build
  hook pins PDFium Chromium 7811 archives and SHA-256 digests, retries downloads
  and uses the official GitHub asset API as fallback. Keep the path overrides
  in the app, Pagecraft and viewer together; standalone package resolution
  does not inherit overrides. Its README documents the persistent cache.
- `flutter_rust_bridge_codegen` 2.13.0 must match the `flutter_rust_bridge`
  version in `rust/Cargo.toml`, `pubspec.yaml` and
  `packages/ferryx_backend/pubspec.yaml`.
- Text-document conversion lives in `ferryx_core::text_document`; changes to
  its API require bridge codegen and `make core` before real-core Dart tests.
  Keep native converter dependency notices in `packages/ferryx_backend/LICENSE`
  so Flutter includes them in the application license bundle.
  Office preview uses pinned `office_oxide` 0.1.16 in that same pipeline,
  over bounded bytes; keep it read-only and do not introduce external office
  applications. Rust fixtures in `ferryx_core/tests/fixtures/office.zip`
  cover DOCX/XLSX/PPTX, DOC/XLS/PPT, embedded images and hidden text.

## Commands

| Task | Command |
|------|---------|
| Deps for root + packages | `make get` |
| Quality gate | `make verify` |
| Format Dart + Rust | `make format` (check only: `make format-check`) |
| Analyze everything | `make analyze` |
| All tests | `make test` (`make test-rust`, `make test-dart`) |
| Native AppKit window tests (macOS + Xcode) | `make test-macos` |
| Host library for real-core tests | `make core` |
| Regenerate bridge | `fvm exec make codegen` (after editing `rust/crates/ferryx_api/src/api/`) |
| Regenerate l10n | `make l10n` (after editing `packages/ferryx_localizations/lib/l10n/*.arb`) |
| Rebuild app icons | `make icons` (after editing a master in `brand/`; needs `rsvg-convert`) |
| Run | `make run` on macOS/Linux; `fvm flutter run -d windows` on Windows |
| Release build | `make build-macos`, `make build-linux`, `make build-windows` |
| macOS disk image | `make dmg` (`build/Ferryx-<version>.dmg`); `make release` publishes it through `gh` |
| Clean, list targets | `make clean`, `make help` |

After codegen or any Rust change, restart `flutter run` fully (`q`,
then run again): a hot restart keeps the old Rust library in the process and
flutter_rust_bridge refuses to initialise ("Content hash … different").
`make core` updates the host library for tests; `make dmg` updates Release.
Neither updates an existing Debug process. Stop that session with `q` and
use `make run` to rebuild Debug and start a new process with matching bindings.

Single package: `cd packages/<pkg> && fvm flutter test` (features:
`packages/features/<name>`). Single crate: `cd rust && cargo test -p ferryx_ops`.
The bridge end to end: `cd rust && cargo test -p ferryx_api` (its tests
take turns on the process-wide state through one mutex).

## Build setup and packaging

Install native desktop tools: Xcode and CocoaPods on macOS, Visual Studio's
Desktop development with C++ on Windows, or Clang/CMake/Ninja/pkg-config,
GTK 3 and C++ development libraries on Linux. CI also installs `liblzma-dev`.
Windows Make targets need GNU Make and a Bash-compatible shell (CI uses Git Bash).

First setup, from the repository root:

```sh
fvm install
rustup update stable
rustup override set stable
rustup component add rustfmt clippy --toolchain stable
fvm flutter doctor -v
make get
```

Universal macOS builds need both Rust targets on the same toolchain:

```sh
rustup target add --toolchain stable aarch64-apple-darwin x86_64-apple-darwin
```

Pagecraft's pinned toolchain is independent. The first native build may
download its toolchain/targets, Cargo dependencies and PDFium from GitHub.
The verified PDFium cache survives `flutter clean`; see the local
[hook/cache guide](packages/pdfium_dart/README.md). Keep the app, reader and
viewer overrides together; they are not inherited between Dart packages.
Real-core Dart tests need the host library built by `make core`.

The macOS `ferryx_api` pod explicitly links the SDK's `bz2` library. ZIP 2's
`bzip2-sys` may select an installed library through `pkg-config` instead of
bundling its C sources. Cargo's `staticlib` does not pass that native linker
requirement to Xcode; keep `s.libraries = 'bz2'` in the podspec. Validate
macOS linking with both a discoverable `bzip2.pc` and the bundled fallback.
After changing a local podspec, run `(cd macos && pod install)` explicitly:
Flutter may reuse Pods when only a plugin's podspec changed.

Release outputs are `build/macos/Build/Products/Release/Ferryx.app`,
`build/windows/x64/runner/Release/` and `build/linux/x64/release/bundle/`
(the latter paths are for x64). Build on the matching OS. Windows/Linux
targets produce application directories, not installers; Linux desktop
entry/icon installation is in [packaging notes](linux/packaging/README.md).

`make dmg` creates `build/Ferryx-<version>.dmg` with an Applications link.
The macOS app is signed ad hoc and is not notarized. `make release` runs
the checks/build/publish steps in [release.sh](tools/macos/release.sh), using
authenticated `gh`. The user commits/pushes first: publishing needs a clean
tree and a commit already on the remote. The tag is `v<version>` from
`pubspec.yaml` without its `+build` suffix. A tag at another commit needs a
version bump; repeating the same commit's release replaces its DMG asset.
The publishing script uploads macOS only.

The [CI workflow](.github/workflows/ci.yml) checks, builds and smoke-launches
Windows/Linux on pull requests, `ci/**` pushes and manual dispatch. There
is no macOS CI job. A launch check does not validate document decoders;
release validation must also open a document in the packaged app.

## Architecture (strict)

See `ARCHITECTURE.md`. The rules that matter most:

- `lib/app` is a thin composition root. `routing.dart` injects dependencies
  into Screen entry points and hands the window's navigation to the
  workspace as callbacks (`WorkspaceNavigation`). No service locator.
- Feature packages never import sibling features. They express navigation
  as callbacks.
- `View` widgets receive only cubit state and UI callbacks.
- Generated bridge code stays inside `packages/ferryx_backend`; repositories
  (`file_repository`, `operations_service`) map it to `domain_models`.
  Features never import `ferryx_backend`.
- Cubit state carries typed codes (`FerryxErrorKind`), never localized
  strings; Views map them with `context.l10n` (`errorMessage`).
- Commands belong in `AppCommand` and the map in `packages/shortcuts`;
  commands may deliberately have no default chord. New actions get a
  command, a label in both ARBs (`cmd…` keys) and an entry in `CommandLabels`;
  `shortcuts_test` fails when a chord does two things in one place.
- The core owns the file system: listings are read, sorted and watched in
  Rust (`open_listing` per panel tab, `DirectoryChanged` events); every
  operation runs in Rust on a thread of its own and reports progress,
  questions and errors through the event stream; the interface never
  touches `dart:io` for files.
- Supported local file changes go on the undo journal: an operation of the
  `Runner` records what it makes, moves, trashes or overwrites through its
  `OpContext` (`record_created`, `record_moved`, `record_overwritten`,
  `record`); a bridge call that changes files itself records through
  `tasks::record`. Trash through `ferryx_vfs::trash` (it keeps receipts);
  permanent deletion and server operations are never recorded. The journal
  is in memory for the process lifetime; overwritten contents cannot be restored.
- A tab may be on a server (`Location.isRemote`; its `server` is a key the
  core makes, never Dart). A command that works on this computer only
  checks the location and says `networkNotOnServer` (`_onServer()`,
  `_notHere` in the workspace); nothing from a server reaches the
  terminal, Jump to Folder or the undo journal. Server waits take a
  `Stop` and a deadline (`remote::runtime`, `remote::blocking`); secrets
  go to the keychain only on Remember, never to preferences or logs.
- A panel's cursor and selection are separate (orthodox manager rules,
  `PanelCubit`): moving the cursor never changes the selection; a command
  works on the selection, else on the focused row, never on `..`.
- The integrated terminal gives the shell every key but its own
  (`CommandScope.terminal`), its place in the window and the window's
  chords no program is given: with ⌘ on macOS, with Ctrl+Shift elsewhere
  (`ShortcutMap.terminalShortcuts`). A window command that must work from
  the terminal needs such a chord; never a plain Ctrl+letter. Its single
  session moves between panel-bottom, a Terminal tab and window placements
  through `TerminalDock`. Preserve the view key, focus scope, PTY and emulator.
  Terminal tabs are presentation state, separate from filesystem tabs, and
  follow their hosting panel; shell input must not reach panel Vim handlers.
- A row is known by `FileEntry.key` (its name; in a flat view its path
  under the root, as two folders may hold one name): selection, quick
  search matches and the cursor kept across a re-read use the key, never
  `name`; where a row is comes from `PanelTabState.locationOf(entry)`.

## Conventions

- Keep comments short and only where they explain an intentional boundary,
  a lifecycle constraint or a non-obvious algorithm.
- Prefer Cubit for command-style state.
- A piece of the interface is a widget class, never a method or function
  that returns widgets (`Widget _buildPanels()`): pass it data and
  callbacks, keep a list child's key on it.
- Tests: Rust unit tests next to the code plus `rust/crates/*/tests`; Dart
  cubit tests with `bloc_test` + `mocktail`, widget tests for shared
  components. Never loosen an assertion to hide an unexplained failure.
- UI: use theme roles (`context.colors`, `context.appColors`,
  `context.text`, `context.metrics`, `AppSpacing`/`AppSizes`); no raw colors
  or sizes in features. Heights of controls, rows and the top row, and every
  radius but `AppRadius.full`, are the platform's: read them from
  `context.metrics`. Check long/overflowing text, keyboard focus rings and
  both themes.
- Native look: Ferryx's Balanced light/dark palette is shared across
  desktops; geometry, typography and interaction follow macOS HIG, Fluent
  and GNOME HIG
  (`AppPlatformStyle`, see ARCHITECTURE.md "Native look on each desktop").
  On macOS, text editing, checkboxes, spinners, scrollbars, icon buttons
  and segmented options use
  `cupertino_ui` behind shared `App*` components. Keep desktop chrome,
  keyboard behavior and metrics; do not substitute mobile sheets, switches
  or sliders indiscriminately. Explicit scrollbars use `AppScrollbar`.
  Compact segmented options use `CupertinoButton` within the shared group
  layout, with one Tab stop, arrow selection and the dedicated
  `segmentedBackground` / `segmentedSelected` / `onSegmentedSelected` roles.
  Features never branch on `defaultTargetPlatform`; a difference belongs in
  the theme or a component-library widget. Menus go through `showAppMenu`,
  pop-up choices through `AppPopupButton`, dialogs through `AppDialog` with
  actions dismissive first (an `OutlinedButton`), notices through
  `showAppNotice`, input through `AppTextField`, labels and help through
  `AppFormField`, search fields through `AppSearchField`, a list picked
  from by typing (a palette, a jump) through `AppQuickPicker`.
- Focus rings: draw them with `FocusRing`, which shows only after keyboard
  use (`FocusHighlightTracker`). Every part of the window the keys can be in
  (each panel, the viewer) is an `AppFocusArea`, which outlines the active one
  and lets a selection read `AppFocusArea.activeOf` to grey itself elsewhere.
- Dialogs open through `showAppDialog` (the theme's barrier, no dismissal
  by a click beside); `AppDialog` owns Return/Esc/⌘. and the default
  action, so never autofocus a button for Return. A body that may not
  fit a low window is an `AppDialogScrollBody`, never a scroll view of
  its own (it would cut the side rings of the fields). Options in a dialog are
  `AppCheckbox`es; `AppToggle` is for settings that act at once. A label
  with a control is an `AppControlRow`; `AppLabelRow` is for a label with
  secondary text only. A name or path that may not fit goes through
  `AppMiddleEllipsis`. Selection colours are `selectionAccent` /
  `selectionMuted` through `AppFocusArea.activeOf`, never `accent` for a
  row. Pair soft active selection with `onSelection` / `onSelectionMuted`;
  `onAccent` belongs on filled accent controls. The active file cursor uses
  `cursorFill` with `onCursor` / `onCursorMuted`; keep its leading line
  independent of marked rows and their check marks. File
  metadata uses `context.mono`, with matching column measurements.
  A table's rows (files, results) take `metrics.tableRowInset` and
  `radius.tableRow`; a sidebar's, picker's or menu's `rowInset` and
  `radius.row`; a sidebar's list pads its rows by `metrics.navRowMargin`.
  A look claimed to be native is measured beside AppKit first
  (ARCHITECTURE.md "Native look"). Strings are never built with
  `join('  ·  ')` or interpolation of separators: use an ARB template
  (`joinedDetails`) with placeholders.
- A text field keeps the keys: `AppTextField` supplies `onEditingComplete`
  by default (Flutter's native default drops focus on Return;
  `test/app/text_field_focus_test.dart` guards the primitive), one waiting on what was typed is
  `readOnly`, never disabled, and one whose code sets its selection (a
  name's stem, a caret) turns `selectAllOnFocus` off — on the desktops it
  is on and replaces that selection. A test of such a field runs with
  `TargetPlatformVariant.only(TargetPlatform.macOS)`, or it cannot see it.
- Nothing the mouse does may lack a keyboard path: a resizable edge is an
  `AppSplitter`, a right-click menu also opens on `AppCommand.contextMenu`
  (`keyboardMenuAnchor`), what a tooltip says shows on focus too
  (`AppTooltip`), and a clickable control answers `ActivateIntent` or wraps
  itself in `HintTarget`, so ⌘J labels it.
- Neighbouring controls in a bar stand `context.metrics.toolbarSpacing`
  apart, groups `AppSpacing.sm`; a panel's bar goes through `AppTopBarRow`.
- Hairlines on the screen's pixels: borders, shapes and dividers through the
  component library's snapping ones (`AppBorder`, `AppRoundedRectangleBorder`,
  `AppOutlineInputBorder`, `AppDivider`, `AppRule`), never Flutter's own
  (`test/app/hairline_sources_test.dart`); a surface placed by centring goes
  in a `PixelSnap`. A rounded box with an edge is an `appEdgedBox` (its
  fill stops inside the edge, so the corners keep it), never a
  `BoxDecoration` with a border and a radius; a `Material` with an edged
  shape does not clip (`ClipInsideEdge` clips its content instead), or the
  edge is clipped away with the content. A `Dialog`'s child is a
  `CentredOnPixels`, so the dialog lands on whole pixels.
- Font weights: the faces may be variable, so change a weight with
  `style.weight(FontWeight.w600)`, never with a bare `copyWith(fontWeight:)`.
  Monospace goes through `context.mono`.
- Form inputs use `AppTextField(monospace: true)` for paths, masks, arguments
  and hashes: it keeps body-sized text and the standard control height.
  Do not build `TextField` or `InputDecoration` in features. Embedded editors
  use the shared `embedded` appearance and their surrounding row's text style;
  inline rename uses `inline`. `AppTextField` keeps focus on Return by default;
  pass `onEditingComplete` only to explicitly hand focus elsewhere.
- Key names never as literal glyphs: use `Chord.label` / `Chord.keyLabel`
  with `context.platform`, and placeholders in ARB strings.
- English case: command labels (`cmd…`, menus) in Title Case ("New
  Folder…"), dialog and window titles in sentence case ("New folder",
  "Connect to server"), as every title here is.
- Localization: add keys to `app_en.arb` (template) and `app_ru.arb`, then
  `make l10n`. File names and paths are never translated. A Russian plural
  takes `one{…}`, never `=1{…}`. Sizes and dates go through
  `FerryxFormatting` (`fileSize`, `dateTime`), never `toStringAsFixed`.
- Data that changes as the user works (visits, recent picks) goes under a
  key of its own through `SideStorage`, throttled, never into the
  preferences blob, which is written whole.
- A capability only some desktops have (Quick Look, the share picker,
  file drags) is a `PlatformCapabilities` flag of the injected
  `PlatformServices` (packages/platform_services), never a platform check.
  Its commands go in `unavailableCommandsFor` (lib/app); every list of
  commands (menus, palette, cheat sheet, hotkeys) skips those
  `!shortcutMap.isAvailable(command)`.
- Vim mode: a key that is a command only with Vim keys on is an
  `AppCommand` named `vim…` (no default chord; bound in `withVimMotions`),
  handled in `PanelView` or through a `PanelHooks` callback; a `:` command
  goes in `_VimActions._runVimCommand`. A text field inside the panels is
  wrapped in `PanelTextGuard`. Cheat sheet and Hotkeys use `Chord.vimLabel`
  when Vim keys are on.
- System archivers use `ferryx_ops::archivers` and `Runner::start_job`:
  fixed CLI adapters, argument vectors, supervised process groups/jobs and
  staging, then core publication for conflicts and Undo. Never put archive
  passwords in argv or execute program discovery probes on the UI thread.
  Settings/workspace get discovery callbacks from the composition root.
- The user manages commits. Do not run destructive git operations.
