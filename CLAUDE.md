# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Toolchain

- Flutter is pinned in `.fvmrc`; always use `fvm flutter` / `fvm dart`
  (every Make target does, except `make codegen`: `flutter_rust_bridge_codegen`
  calls Flutter/Dart on PATH; use `fvm exec make codegen` to supply the
  project's pinned SDK).
- Rust builds inside the Flutter build go through cargokit, which runs
  `rustup run stable cargo`. Keep the rustup toolchain current
  (`rustup update stable`). `rust_builder/cargokit/build_pod.sh` pins
  `RUSTC` to the rustup toolchain so a Homebrew Rust ahead on PATH cannot
  link a std built for the host's macOS.
  The Makefile calls `cargo` from PATH; keep it on that same toolchain.
  The workspace's declared `rust-version = "1.85"` is below the current
  lockfile's requirements: the RAR dependencies require at least 1.97.1.
  CI uses stable and does not verify the declared minimum.
- `flutter_rust_bridge_codegen` 2.13.0 must match the `flutter_rust_bridge`
  version in `rust/Cargo.toml`, `pubspec.yaml` and
  `packages/ferryx_backend/pubspec.yaml`.

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
| Regenerate bridge | `make codegen` (after editing `rust/crates/ferryx_api/src/api/`) |
| Regenerate l10n | `make l10n` (after editing `packages/ferryx_localizations/lib/l10n/*.arb`) |
| Rebuild app icons | `make icons` (after editing a master in `brand/`; needs `rsvg-convert`) |
| Run | `make run` on macOS/Linux; `fvm flutter run -d windows` on Windows |
| Release build | `make build-macos`, `make build-linux`, `make build-windows` |
| macOS disk image | `make dmg` (`build/Ferryx-<version>.dmg`); `make release` publishes it through `gh` |
| Clean, list targets | `make clean`, `make help` |

After `make codegen` or any Rust change, restart `flutter run` fully (`q`,
then run again): a hot restart keeps the old Rust library in the process and
flutter_rust_bridge refuses to initialise ("Content hash … different").

Single package: `cd packages/<pkg> && fvm flutter test` (features:
`packages/features/<name>`). Single crate: `cd rust && cargo test -p ferryx_ops`.
The bridge end to end: `cd rust && cargo test -p ferryx_api` (its tests
take turns on the process-wide state through one mutex).

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
  the terminal needs such a chord; never a plain Ctrl+letter.
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
  Features never branch on `defaultTargetPlatform`; a difference belongs in
  the theme or a component-library widget. Menus go through `showAppMenu`,
  pop-up choices through `AppPopupButton`, dialogs through `AppDialog` with
  actions dismissive first (an `OutlinedButton`), notices through
  `showAppNotice`, search fields through `AppSearchField`, a list picked
  from by typing (a palette, a jump) through `AppQuickPicker`.
- Focus rings: draw them with `FocusRing`, which shows only after keyboard
  use (`FocusHighlightTracker`). Every part of the window the keys can be in
  (each panel, the viewer) is an `AppFocusArea`, which bars the active one
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
  `onAccent` belongs on filled accent controls. Keep the file cursor's
  leading line independent of marked rows and their check marks. File
  metadata uses `context.mono`, with matching column measurements.
  A table's rows (files, results) take `metrics.tableRowInset` and
  `radius.tableRow`; a sidebar's, picker's or menu's `rowInset` and
  `radius.row`; a sidebar's list pads its rows by `metrics.navRowMargin`.
  A look claimed to be native is measured beside AppKit first
  (ARCHITECTURE.md "Native look"). Strings are never built with
  `join('  ·  ')` or interpolation of separators: use an ARB template
  (`joinedDetails`) with placeholders.
- A text field keeps the keys: one that submits on Return has an
  `onEditingComplete` (`() {}` keeps the focus; Flutter's default drops it,
  `test/app/text_field_focus_test.dart`), one waiting on what was typed is
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
- The user manages commits. Do not run destructive git operations.
