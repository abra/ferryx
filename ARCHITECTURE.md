# Ferryx Architecture

Maintainer-facing map of the codebase. Keep it aligned with real code when
changing package boundaries, dependency flow, startup, routing or the
bridge. The code remains the source of truth; if this document and the
implementation diverge, fix both in the same change.

## Style

Ferryx follows the multi-package Flutter architecture of Mnema (feature
packages, specialised infrastructure packages, a thin composition root)
and its Flutter ⇄ Rust split: a Rust workspace owns the file system and
every operation on it, Flutter owns presentation, and change notifications
flow from Rust to Dart through one event stream.

```
lib/app  ─► features/* Screen or show… dialog entry points
             ─► feature Cubit
                 ─► repository/service contracts (Dart)
                     ─► ferryx_backend (generated bridge + mapping)
                         ─► rust/crates/ferryx_api ─► ferryx_vfs  (listings, watching, archives…)
                                                   ─► ferryx_ops  (copy, move, delete, compress, find…)
                                                   ─► ferryx_core (sorting, masks, batch rename)
                                                   ─► ferryx_term (the terminal's shell)

features/* never import sibling features.
```

### Native look on each desktop

One layout, three sets of conventions: the theme follows Apple's Human
Interface Guidelines on macOS (with macOS 26's own metrics, `MacGeneration`),
Fluent on Windows 11 and the GNOME HIG (libadwaita) on Linux.
`AppPlatformStyle` is picked from the platform in the composition root
(`AppTheme.of(style, brightness, generation:)`), and everything a desktop
draws differently comes from the theme, never from `defaultTargetPlatform`
in feature code: type (`AppTypography`), colour (`AppPalette`, six
palettes, `AppColorsExt` roles), metrics (`AppMetrics`: control, row and
menu heights, radii, the top row, focus rings, insets) and the shared
controls (`AppNavItem`, `showAppMenu`, `AppDialog`, `AppToggle`,
`AppSegmentedControl`, `AppPopupButton`, `AppTabStrip`, `AppSplitter`,
`AppTopBarRow`, `FocusRing`, tooltips, overlay scrollbars). Hairlines snap
to device pixels (`AppBorder`, `AppDivider`, `PixelSnap`). The component
library is shared with Mnema and documented there in depth; Ferryx adds
file icons (`AppIcons`), the tag palette (`AppColorsExt.ink/wash` by
index) and Finder's tag colours (`AppTagColors`, `AppTagDots`).

The HIG details the library keeps for every screen, so features need
not:

- Selection: `selectionAccent` (NSColor.selectedContentBackgroundColor, a
  shade deeper than the button accent) with `onAccent` text where the
  keys are, `selectionMuted` (the unemphasized grey) everywhere else —
  another panel, or the whole window while it is not the active one
  (`AppWindowActivity` at the app root, read by `AppFocusArea.activeOf`).
  A list row's highlight is rounded (`radius.row`) and inset from the
  list's edge (`metrics.rowInset`), as Finder's since macOS 11; rows are
  `metrics.listRowHeight` tall.
- Focus: a text field keeps its bezel and takes the accent halo outside it
  on any focus (`AppOutlineInputBorder.halo`); buttons, pop-ups, boxes and
  switches draw `FocusRing` in keyboard mode only (a ⌘ or ⌃ chord does not
  switch that mode on).
- Dialogs: `AppDialog` runs the default (last) action on Return whatever
  has the focus, keeps Return for a focused field's submit, leaves on Esc
  and ⌘., holds the focus itself when nothing asked for it, never makes a
  `destructive` action the default, wraps its buttons (each at least 68
  wide, 12 apart, 20 from the edge), and does not dim the window behind a
  macOS sheet; `showAppDialog` opens one with the theme's barrier and no
  dismissal by a click beside it. Options a dialog's button applies are
  `AppCheckbox`es (Space flips, the label is part of the target, a mixed
  state for several items); a switch (`AppToggle`) is for a setting that
  acts at once. A label with a control is an `AppControlRow` (the control
  is never squeezed or dropped); `AppLabelRow` is for a label with
  secondary text.
- Menus: the check column is always kept on macOS and the icon column
  whenever an item has one, so labels line up; key equivalents are set in
  the menu's own size in the secondary colour; a pointer leaving the menu
  takes the highlight with it; a pop-up button shows the two chevrons of
  an NSPopUpButton. A search field clears with its button or Esc.
- Text: a file name or a path that does not fit loses its middle
  (`AppMiddleEllipsis`), never its extension; figures in columns and
  footers are tabular; secondary text is `textMuted` (AA on every
  surface), `textFaint` is for placeholders and disabled text only.

### Window chrome

`WindowFrame` (`lib/app/window_frame.dart`) decides at start-up who draws
the title bar: on macOS the system bar is hidden and the runner centres the
traffic lights in the app's top row (`macos/Runner/MainFlutterWindow.swift`);
on GNOME the app draws the header bar's buttons; elsewhere the system bar
stays. `WindowDecor` carries the insets to the screens: the left panel's
header keeps the traffic lights' room, the right panel's the trailing
buttons'. The window is shown only after the preferences are read
(`showWindow`), at its remembered frame fitted to the screens, and
`WindowStateSaver` writes moves and resizes back.

## Rust workspace (`rust/`)

| Crate | Responsibility |
|-------|----------------|
| `ferryx_core` | Pure logic: the `Entry` of a panel row, natural / case-insensitive / case-sensitive collation (`collation`), sorting by field with folders first and extensionless folders (`sorting`), file masks and regular expressions (`mask`), quick-search matching with the ranges to underline (`quick_search`), and the batch-rename language (`batch_rename`: placeholders, substrings, dates, counters, case commands, then search and replace and a case change). No I/O. |
| `ferryx_vfs` | The file system: a folder's rows with their metadata (size, times, the macOS added time through `getattrlist`, mode, owner and group names, BSD flags, hidden), one entry, byte ranges of a file (`native`); archives as read-only folders (`archive`: zip, tar with any compression, 7z, rar, iso, single compressed files; see Archives below); a folder watched for changes reported once per burst (`watch`, `notify`); the volumes (`volumes`, `sysinfo`) and the free space; the standard folders, opening with the desktop or an application, revealing in the file manager, the trash, ejecting (`system`); permissions, flags, owners and times read and written (`attrs`); symbolic and hard links (`links`). Every error is a `VfsError` with a kind the interface words. |
| `ferryx_ops` | Operations on threads with progress, pause, cancellation and questions: copy and move (a rename on the same volume, else a copy and a delete; folders merge; conflicts ask or follow the policy; attributes preserved; optional verification), duplicate (`name copy.ext`), extract out of an archive, delete and trash, compress to zip (deflate, optional AES-256), folder sizes, plus Find Files (`find`: name, contents in overlapping windows, size, streamed hits) and the application of a batch rename (`rename`: staged through temporary names when names swap). `Runner` holds every operation; `OpContext` is what an operation checks, reports and asks through. |
| `ferryx_term` | The integrated terminal's shell: a `Session` runs the user's shell as a login shell in a pseudo-terminal (`portable-pty`: openpty, ConPTY on Windows), sends its output in batches with flow control, probes whether it waits at its prompt (`tcgetpgrp`) and its folder (`proc_pidinfo`, `/proc/<pid>/cwd`), types `cd` when asked, and hangs up and reaps it on close. No emulation: that is the interface's. |
| `ferryx_api` | `flutter_rust_bridge` surface. Holds the open listings (`app.rs`: one per panel tab, with its raw rows for resorting and its watcher), the archive indexes, the operations runner (whose listener forwards progress as events) and the searches; converts to plain DTOs (`api/types.rs`, `…View` types, enums without payloads so Dart sees enums, `i64` counts so Dart sees `int`); `volume_id` names a path's volume for a drop to tell a move from a copy. Its `Cargo.toml` uses literal fields because cargokit parses it without workspace inheritance. |

The Operations stream adds to `ferryx_ops` the undo journal (`journal`,
`undo`), folder comparison and synchronization (`sync`), checksums
(`checksum`, `hashing`) and duplicates (`duplicates`); to `ferryx_vfs` the
trash with receipts (`trash`); to `ferryx_api` the files `journal.rs`,
`sync.rs`, `checksum.rs`, `duplicates.rs` and `tasks.rs` (ids, cancel
flags and event batching of the dialogs' work). `Runner::start_job` runs a
module's own job as an operation, with how its changes go on record
(`Journaling`). See "Operations stream" below.

The Network stream adds to `ferryx_vfs` the module `remote` (servers over
SFTP, FTP/FTPS and WebDAV behind one trait, their connections, host keys,
the keychain), to `ferryx_ops` the module `transfer` (copy, move, delete
and folder sizes with a server on a side), to `ferryx_api` the file
`api/network.rs`, and the crate `ferryx_test_servers` (in-process SFTP,
FTP and WebDAV servers for the tests; never shipped). See "Network
locations" below.

Rules:

- A panel's listing lives in Rust while the panel shows it
  (`open_listing(listing_id, location, options)`): the rows are read once,
  sorted there, and resorted from the cache (`resort_listing`) without
  reading the disk again; a change of hidden items reads again. The
  folder is watched and `DirectoryChanged` names the listing; the panel
  then calls `refresh_listing`, keeping its cursor and selection by name.
- Locations are native paths, `(archive, inner path)` or `(server key,
  path)`; a listing inside an archive comes from the archive's index and
  is not watched (the archive's folder is); one on a server is read over
  the network and not watched either (see Network locations).
- Operations never block the bridge: `start_operation` answers an id at
  once and every change comes as an `OperationProgress` event (throttled
  to one report per 100 ms while bytes flow, at once on a state change).
  A question (`Conflict` with both sides, `Error` with retry/skip/stop)
  puts the operation in `Waiting` until `answer_operation`; an "…All"
  answer sticks for the rest of the operation.
- Folder sizes are an operation (`CalcSizes`) whose progress carries the
  sizes done so far; the panel merges them into its rows by name.
- Find Files runs on a thread and sends hits in batches (`FindProgress`,
  at most every 80 ms or 200 hits) and `FindDone` at the end or on cancel.
- With "Use the Spotlight index" (offered where `capabilities().spotlight`
  says `mdfind` is there) `find::search` asks Spotlight first
  (`ferryx_ops::spotlight`): `mdfind -0 -onlyin <root>` with a query made of
  the mask's parts as file-name matches (`?` and `[…]` widened to `*`),
  each word of the contents as a word prefix and the size as a bound; the
  paths stream from a reader thread, so a cancel kills `mdfind` within a
  tenth of a second. Every hit is then checked here as a walk would check
  it (`find::Matcher`: the exact mask or the regular expression, hidden
  items, folders, size, the contents read for case, a whole phrase or "not
  containing"), so Spotlight only narrows the candidates. When `mdfind`
  cannot run or fails without a hit, the folders are walked instead and
  `FindDone` says so (`find_spotlight_failed`, a notice in the dialog).
  Spotlight skips system folders, hidden folders and the folders excluded
  in System Settings — the option's note says so. (Live: `/Applications`'
  67 apps in 0.16 s.)

- A terminal session's output, state and end come on a stream of its own
  (`terminal_events`), not the app's event stream: they are high-volume
  and flow-controlled (see "The integrated terminal").

Tests: `cargo test --workspace`. `ferryx_api/tests/api_flow.rs` runs the
bridge end to end (listings, resorting, the watcher's event, archives,
operations with a question answered, folder sizes, batch rename, find);
the tests take turns on the process-wide state. `terminal_flow.rs` runs a
`/bin/sh` session through the bridge.

### Archives

`ferryx_vfs::archive` reads zip (jar, apk, ipa, whl), tar alone or with
gzip, bzip2, xz or zstd, 7z, rar, ISO 9660 images and a single file
compressed with gzip, bzip2, xz or zstd (an archive of one member named
without the compression's extension). `detect` reads a file's first bytes
before its name: a `.zip` that is a 7z opens as one, a `.gz` that holds a
tar is a tar, and ⌘↓ (`detect_archive`) opens an archive of any name;
`is_archive` (Return) asks the name only, so it costs no I/O per row.

- **One index per archive.** `ArchiveIndex` keeps the members sorted by
  path with each folder's children (a folder lists in the time its own
  rows take; a subtree, for a flat view or an extraction, is one
  contiguous run). It is read from the archive's directory where the
  format has one (zip central directory, 7z headers, rar headers, iso
  directory records) and in one pass over the stream otherwise (tar, a
  plain tar seeking past each member's data). `archive::shared` keeps the
  last eight indexes for the whole process, keyed by path and checked
  against the file's modification time and length, and reads a new one
  outside its lock so a large archive never holds up another listing.
  Measured (release, M-series Mac): a 50 000-member zip opens in 0.2 s, a
  50 000-member tar.gz in 0.07 s; a folder of a thousand members lists in
  0.06 ms, the whole tree flat in 7 ms.
- **Streaming reads.** `extract_members` hands members to a `MemberSink`
  (begin, write, end) in the archive's own order: a tar stream once
  whatever the number of members, a 7z block decoded once for all the
  members it holds (members of a solid block passed by are drained, never
  kept), rar in member order, iso extents read straight from the image. No
  member is held whole in memory; the viewer's ranges of a member over
  4 MiB come from a copy unpacked once to the temporary folder.
- **Passwords.** An encrypted member list (7z `-mhe`, rar `-hp`) answers
  `PasswordRequired` until `set_archive_password` gives one that opens it;
  encrypted members (zip AES and ZipCrypto, 7z AES, rar) are read with the
  password kept for the archive. A password is tried before it is kept
  (the member list, or the first 64 KiB of the smallest encrypted member),
  so a wrong one is the typed `WrongPassword`, never a crash or garbage.
  The interface asks in a dialog that stays until a password opens the
  archive (`showArchivePasswordDialog`): when a panel enters an archive
  whose list is encrypted (`PanelTabState.passwordLocation`, the panel's
  `onArchivePassword` hook), before a member is opened, viewed or copied
  out, and in Extract To's own password field.
- **Extract** (`ferryx_ops::extract`, `OpKind::Extract`): members out of
  an archive (F5 inside one, ⌥F9 there with a dialog), or whole archives
  on disk (Extract To, ⌥F9, `:extract [dir]`) each into the destination or
  into a folder named after it (`into_folders`, `archive_stem`: `site.tar.gz`
  → `site`). The dialog turns that option on when an archive holds more
  than one item at its root, as Archive Utility does, and the user can
  turn it either way. Conflicts follow the policy or ask, a member that
  fails asks to skip or stop (a stream cannot retry), a missing or wrong
  password passes that archive by with an error, folders are made even
  when empty, modes and times are kept, symbolic links are made as links,
  and member paths never climb out of the destination (`..` is dropped).
- **Crates.** All pure Rust except zstd and the zip crate's bzip2, which
  were in already: `sevenz-rust2` 0.20 (the last release for Rust 1.85;
  AES, LZMA/LZMA2, BZip2, Deflate, PPMd, Zstd), `unrar-rs` (a Rust port of
  RARLAB's UnRAR, RAR 1.5–5, solid and encrypted archives; built with
  `crypto-rust` so no C toolchain is needed — the default AWS-LC backend
  wants CMake), `lzma-rust2` (xz, the one `sevenz-rust2` uses), `bzip2` 0.6
  (its default backend is the pure-Rust `libbz2-rs-sys`). `lzma-rust2`
  comes from `rust/vendor/lzma-rust2` through `[patch.crates-io]`: 0.16.5
  with a progress check in its LZMA and LZMA2 read loops, which spun
  forever on about one wrong 7z password in ten (`FERRYX.md` there; 0.23
  has the same loop). A password is also refused when the member read
  with it ends short, as a wrong key's garbage can (`check_password`). The official
  `unrar` crate compiles RARLAB's C++ sources: mature, but a C++ build
  through cargokit for every target; `unrar-rs` reads the same formats
  with none. Both carry the UnRAR licence: free to use for extraction,
  never to make a RAR compressor — Ferryx only extracts, and the licence
  text ships with the crate. ISO 9660 is read by Ferryx's own small
  reader (`archive/iso.rs`): primary and Joliet descriptors, Rock Ridge
  `NM`/`PX`/`SL`, files of several extents.

## Bridge (`packages/ferryx_backend`)

Generated code lives in `lib/src/rust/` and is regenerated with
`make codegen` from `flutter_rust_bridge.yaml`. Repositories import the
package with a prefix (`as rust`) and translate through `mapping.dart`;
feature packages never see generated types. `FerryxBackend.guard` turns
Rust errors into `FerryxException` (typed `FerryxErrorKind`, the core's
message and path, no localized text). Timestamps cross as Unix
milliseconds and become local `DateTime`s in the mapping.

`rust_builder/` (cargokit) compiles `ferryx_api` into the platform library
that `ferryx_backend` loads, as part of the Flutter build.

## Dart packages

| Package | Role |
|---------|------|
| `domain_models` | Pure Dart contracts: `FileEntry`, `Listing`, `Location`, `SortOptions`, `ListingOptions`, `Volume`, `StandardFolders`, `OperationRequest`/`OperationProgress`/`OperationQuestion`, `FindRequest`/`FindHit`/`FindUpdate`, `RenameOptions`/`RenameOutcome`, `FileAttributes`/`AttributeChanges`, `Favorite`, `PanelLayout`, `ExternalEditor`/`ExternalTool`, `FerryxException`, `ArchiveInfo`, `FlatStart`/`FlatBatch`, `FileTag`/`TagOutcome`, `Capabilities`. |
| `ferryx_backend` | The generated bridge, `FerryxBackend` (init, the event stream, `guard`) and `mapping.dart`. |
| `monitoring` | `Logger` and the console observer. |
| `shortcuts` | `AppCommand` (scopes: global, panel, viewer, lists, dialogs, terminal; `CommandSection` for the palette's groups), `Chord`, `ShortcutMap` (defaults per desktop, `forUser` with overrides), the `CommandHandlers` dispatch chain (`commandsAt` answers what a place handles), `ChordCodec`. |
| `preferences_service` | Installation preferences (theme, locale, text scale, shortcut overrides, window frame, the panels' state, layouts, sorting defaults, quick search, favorites, editors, tools, confirmations, copy defaults, viewer, the terminal's settings and place) + `PreferencesScope` and `PreferenceBuilder`; beside the blob, under keys of their own (`SideStorage`), `FolderFrecency` (the folders visited) and `RecentItems` (the commands run lately). |
| `file_repository` | `FileRepository`: listings (open, refresh, resort, close, peek), items (stat, byte ranges, extract to temp, make, rename, links, resolve), the system (volumes, standard folders, free space, open, open with, reveal, eject, applications), attributes; archives (what one holds, its password, detection by its bytes); flat listings (open with their stream of batches, the order of their rows); Finder tags (a listing's, edits) and the desktop's `capabilities`; `directoryChanges` names listings whose folders changed. |
| `operations_service` | `OperationsService` (start, pause, resume, cancel, answer, forget; `progress` stream and the latest report per operation; `run` waits for one), `FindService` (start, cancel, `updates`), `RenameService` (preview, apply). |
| `platform_services` | What only some desktops offer, behind one injected `PlatformServices` (capabilities; Quick Look; the share picker; file drags out of the window): `ChannelPlatformServices` on macOS (the runner's `ferryx/platform` channel), `DesktopPlatformServices` elsewhere (drags only), `FakePlatformServices` for tests (`testing.dart`); `PlatformDropArea`, the window's one drop region (super_drag_and_drop). |
| `terminal_service` | `TerminalService.start` → a `TerminalSession` (its `updates`: `TerminalOutput`, `TerminalShellState`, `TerminalExited`; write, resize, ack, state, change directory, close) over `ferryx_api`'s terminal; the default shell's name. |
| `ferryx_localizations` | ARB-generated `FerryxLocalizations`, command and scope labels, formatting helpers (sizes, dates, durations, error titles, operation titles, answers, columns). |
| `component_library` | Tokens, the platform-adaptive theme and the desktop widgets (see Native look); for drags, `FileDragSource` (past `metrics.dragThreshold`), `FileDropTarget` (found by hit-testing) and `AppDropOutline`. |
| `features/panels` | The main window (`WorkspaceScreen`): two `PanelView`s with a `PanelCubit` each, the edge between them, the integrated terminal's place (`TerminalDock`, the view injected as a `WorkspaceTerminal`), the operations cards, every file command (`workspace_actions.dart`), the row and panel menus, and the dialogs: copy / move / copy as / move as, new folder, delete, compress, select by mask, go to folder, links, favorites, the Go To pop-up and the quick lists, batch rename, file attributes, Extract To and an archive's password, the tag menu and a new tag, and the questions of operations; a tab's flat view (`FlatView`). |
| `features/viewer` | The built-in viewer (`ViewerScreen`): text, hex and preview over a `ViewerSource` (a file on disk or an archive member), windows of large files, find and go to. |
| `features/find` | Find Files (`showFindDialog`, `FindCubit`): the form (with the Spotlight option where the desktop has it), the streaming results, go to a hit or view it. |
| `features/settings` | The settings window (`SettingsScreen`: General, Panels, Viewer, Terminal, Hotkeys, Editors, Tools, About) and the cheat sheet (`showCheatSheet`). |
| `features/palette` | The command palette (`showCommandPalette`, `PaletteCubit`, the `fuzzyMatch` scorer). |
| `features/terminal` | The integrated terminal: `TerminalSessionCubit` (the session, the xterm.dart emulator it writes into, `FolderSync`), `TerminalPane` (its bar, the emulator in the theme's colours, the end notice, the menu) and `TerminalKeys` (which keys are the window's). |
| `features/sync` | Synchronize Folders (`showSyncDialog`, `SyncCubit`): two trees compared in the core, a virtual table with an action per row, the synchronization as an operation. |
| `features/checksums` | Checksums (`showChecksumsDialog`, `ChecksumsCubit`): hashes of files or the check of a checksum file. |
| `features/duplicates` | Find Duplicates (`showDuplicatesDialog`, `DuplicatesCubit`): groups of identical files, marks, Move to Trash. |
| `network_service` | `NetworkService` over the core (`CoreNetworkService`): addresses read and keyed by Rust, connections made (cancellable) and closed, their state (`serverChanges`), the questions a connection asks and their answers, a saved password forgotten, a temporary folder per server; `FakeNetworkService` for tests (`testing.dart`). |
| `features/network` | Connect to Server (`showConnectDialog`, `ConnectCubit`: the address field, the saved and recent servers), the server editor, the host key, password, passphrase and prompts dialogs and the changed-key alarm, `NetworkPromptHost` (shows a connection's questions one at a time, closes the ones withdrawn), `ServerConnector` (a server connected to again with its saved way of logging in, an address typed). |

### Feature wiring

`routing.dart` → `Screen` → `Cubit` → `View`. Dependencies are injected at
`routing.dart`; the workspace is given a `WorkspaceNavigation` whose
callbacks open the viewer route, the find dialog, the settings route and
the cheat sheet, so the panels feature never imports those features. The
integrated terminal comes the same way: a `WorkspaceTerminal` (a factory
for its controller and a builder for its view) that `lib/app/terminal_link.dart`
fills from the terminal feature. The workspace reports its state (`WorkspaceSnapshot`: both panels' tabs, the
active side, the split) and the routing writes it to the preferences,
debounced, and names the active folder in the window title.

### The panels

`PanelCubit` (one per side) keeps `PanelState`: the tabs, each a
`PanelTabState` with its location, the listing the core holds for it, the
rows shown (the listing less what a quick search hides, with calculated
folder sizes merged), the cursor (an index into the rows), the selection
(names; `..` is never selected), the history, the quick search and its
match ranges, the sort options and the layout index. Rules:

- Return enters a folder or an archive, goes up on `..`, and otherwise
  answers an `OpenFileRequest` the workspace opens with the desktop (an
  archive member is extracted to a temporary folder first). ⌘↓ enters the
  focused item as an archive whatever its extension.
- Going up puts the cursor on the folder left; reading again after a
  change keeps the cursor on its name and the selection by names.
- Shift with a movement selects or deselects the rows from the cursor up
  to the target, as the first row of the run decided (`rangeSelecting`); a
  plain movement ends the run. A click moves the cursor only; with the
  primary modifier it flips the row, with Shift it extends the run to the
  clicked row.
- A command works on `targets`: the selection in row order, else the
  focused row unless it is `..`.
- The cursor row takes the emphasized selection colour in the active
  panel of the active window and the unemphasized grey elsewhere; the
  selected rows keep a tint of the accent with link-coloured text in the
  active panel (so cursor and selection read apart, as orthodox managers
  need) and grey too where the focus is not (`RowLook`, through
  `AppFocusArea.activeOf`).
- Quick search: letters typed in the panel (unless a modifier is required
  by the preferences) filter or underline; the cursor goes to the first
  match; Backspace takes a letter back while a search is on, Esc clears.
  Space, `/` and `~` are keys of their own until a search is on.
- The view measures itself (`PanelGeometry`: rows per page and per brief
  column) and tells the cubit, so PageUp/Down and ←/→ in brief mode move
  by what fits.
- Tabs: a new tab opens after the active one at the same place; closing
  shows the neighbour and remembers the location for ⇧⌘R; the last tab of
  a panel never closes; each tab's listing is closed in the core with it.
- The panels' state is saved to the preferences as the workspace reports
  it (`SavedPanel`: locations, sort, layout, the tab shown, the closed
  ones), and read back at start; a saved folder that is gone falls back
  to the home folder, then the root.

### Flat view

⌥⌘B (Vim `zf`, `:flat`) turns a tab into Total Commander's branch view:
every file under its folder in one list, each row with its folder
relative to the tab's in the secondary colour after the name
(`FileEntry.folder`; in List the name column holds both and the data
columns give way to it sooner, `ColumnWidths.flatNameMin`; a long name
keeps three fifths of the room and its extension, a long folder its last
letters). Folders are not rows — an empty folder shows nothing — and a
symbolic link to a folder is a row, never followed, so a link cannot make
the walk go round. Hidden items follow the preference, a hidden folder
with all it holds. The footer's capsule says "Flat" (with the spinner
while the tree is read) and the count says files; Esc (once no search is
on), the command again, the capsule, or going anywhere else leaves it,
the cursor landing on the item that holds the row it was on. Inside an
archive the view comes from the index, in memory. A tab saved for the
next run keeps its folder, not its flat view.

- **Keys.** Rows of one name in two folders are two rows: a row's key is
  its path under the root (`FileEntry.key`, the name in a plain listing),
  and the selection, the quick search's matches, the cursor kept across a
  re-read and the list's row keys all use it. Commands work on the
  targets' real paths, so copy, move, delete, rename, open and the viewer
  work unchanged; `PanelTabState.locationOf` is where a row is.
- **Streaming.** `open_flat_listing` answers the header and a generation;
  `stream_flat_listing` walks on a thread of its own (`ferryx_vfs::flat`,
  walkdir, cancellable) and sends rows on a stream of their own in batches
  — the first after 200 rows or 30 ms, then every 5 000 rows or 120 ms —
  so the first rows show at once and each batch is decoded as it arrives.
  The walk stops at 200 000 rows and says so (`capped`, "the first 200 000
  files"). Rows show in walk order while they come; at the end
  `sort_flat_listing` answers the order as indices into the rows sent, so
  a sort never sends the rows again (by name, rows of one name keep their
  folders' order). A sort asked meanwhile applies when the walk ends.
- **Refresh.** The tab's folder is watched, not its subfolders: a change
  there, ⌘R, the hidden items shown or not, or an operation that wrote
  into or took from the tree (`PanelCubit._walkFlatViewsUnder`) walks the
  tree again. A walk again keeps the rows shown and swaps in the new ones
  when it ends (no flicker; cursor and selection stay by key); a change
  during one asks for one more after it. Changes deeper in the tree by
  other programs need ⌘R: watching a whole tree is costly (inotify keeps
  a watch per folder) and re-reading it on every change of a busy tree
  (`~/Library`) would never rest.
- **Measured** (release, M-series Mac, warm cache): `~/Library`, capped at
  200 000 files — first rows after 24 ms, all after 7–9 s, sorted by name
  in 0.33 s; `/usr`, 22 000 files — first rows after 14 ms, all after
  0.5–0.7 s, sorted in 14 ms. Sorting needed the natural collation to
  stop allocating a string per character compared (it took 3.9 s for the
  200 000 rows before; every listing's sort gains the same). The panel
  appends each batch (only the new rows meet the quick search), Brief
  mode sizes its columns as thirds (as it now does for any list over
  2 000 rows), and only the rows in view are built.

### Finder tags

macOS keeps tags in the extended attribute
`com.apple.metadata:_kMDItemUserTags` (a binary property list of
`Name\nColour` strings); `ferryx_vfs::tags` reads and writes it on the
item itself (never through a link) and keeps the legacy Finder-info
colour label in step (the last coloured tag's), so older tools agree.
`capabilities()` says whether the desktop has tags (macOS) and whether
Spotlight answers (`mdfind`); the routing passes them to the workspace
(`WorkspaceScreen.capabilities`) and to Settings (`unavailable`
commands), so ⌃⌘T, its menu items and its Hotkeys row are hidden
elsewhere — features never ask the platform.

- **Read lazily.** One `getxattr` costs about 14 µs on APFS even for an
  item without tags, more than the rest of its row (10 000 files: 0.06–0.1 s
  to list, 0.14–0.16 s more for the tags), so a listing does not read
  them. `PanelCubit` (`readTags`) asks `read_listing_tags` once a listing
  or a flat view shows — read on up to four threads, only the tagged
  items come back — and merges them in by path; a listing read again keeps
  the dots it showed until the new read answers, so they never blink. One
  item (`stat`) reads its own.
- **Shown** as Finder does: up to three dots right after the name in List
  and Brief (`AppTagDots`, Finder's colours in light and dark from
  `AppTagColors`, each ringed with the row's background so they stay
  apart on the cursor's accent too), the names in the dots' tip and the
  row's semantics; uncoloured tags have no dot.
- **Edited** with ⌃⌘T (the row menu's "Tags…", `:tag red,work`,
  `:tag -red`): a menu by the cursor's row lists Finder's seven colours in
  its order, then the named tags of the folder's rows, each checked when
  every target has it, with a dash when some do (`AppMenuAction.mixed`);
  a pick turns it on for all, or off when all had it; "New Tag…" asks a
  name and a colour. `set_tags` applies one edit to every target and
  answers each one's tags or its typed failure; the window shows the new
  tags in both panels at once and words the failures in one notice. A
  standard tag is matched by its colour and its name in the interface's
  language or an English Finder's, and taken off under both.

### Keyboard model

- A single `CommandIntent` type carries an `AppCommand`. `CommandShortcuts`
  at the app root (global scope only) raises intents; `CommandDispatcherAction`
  walks the `CommandHandlers` chain from the focused widget outward.
- The workspace installs the `panel` scope around the panels, so the
  arrows, Return, Backspace, Tab, Space and the function keys reach the
  active panel's handlers and never a dialog's field. The viewer installs
  its own scope; the viewer's ⌘1–⌘3 win over the global quick lists there
  because the inner `Shortcuts` is consulted first.
- A panel's own `Focus.onKeyEvent` takes typed characters for the quick
  search before the shortcuts see them, so `/` and `~` are commands only
  while no search is on.
- Chords are written once for every desktop (`Chord.primary` is ⌘ or
  Ctrl); where Windows and Linux press another key (Del for the trash,
  Shift+F10 for the menu, ⌃⇧ arrows for the split where Ctrl+Alt is AltGr)
  `ShortcutMap.defaults(platform)` lays `_otherDesktops` over the table.
  `ShortcutMap.forUser` applies the user's overrides; the app
  (`DependenciesContainer.shortcutMap`) and Settings → Hotkeys build the
  map the same way.
- `KeyHintStrip` under the panels shows the keys for the active panel's
  state (`hintsFor`, a pure function over `PanelTabState`: a file, a
  folder, `..`, a selection, the quick search, the Vim prompt and Visual
  mode, an empty folder), with chords and labels from the shortcut map
  and the strings, so a rebound key shows as bound; `Preferences.showKeyHints`
  turns it off (its own close button, Settings → General).
- The panel's key map also holds the window's two-key sequences
  (`toShortcuts(sequencesOf:)`), tried before its own keys, so `gn`, `cd`,
  `gj` complete from a panel instead of running its `n`, `d`, `j`; a
  prefix never arms while a text field has the focus, so `g` is a letter
  in a picker or a dialog's field.
- Hint mode (⌘J) labels every clickable thing on the topmost route; the
  menu key (⌃↩, ⇧F10, Menu) opens the focused row's menu by its row; the
  edge between the panels takes the keys with ⌥⌘\ (`AppSplitter`).
- The integrated terminal is outside the panel scope, so no panel key
  fires there; the emulator reads a key before any `Shortcuts` above it,
  so `TerminalPane` asks `TerminalKeys` first (see "The integrated
  terminal").

### Vim mode

Settings → Panels → "Vim keys" (`Preferences.vimMode`) lays a second key
table over the panel scope; nothing else in the window changes.

- `ShortcutMap.forUser(vimMotions: true)` applies `withVimMotions`: `j k`
  move, `h` is the parent and `l` enters (ranger's reading of the home
  row), `gg` / `G`, `H M L`, `zz zt zb`, `w` / `b` step columns in Brief,
  `f` / `F` / `;` / `,`, marks `m` and `'`, `v` / `V` Visual, `x` and Space
  select, `*` / `#` by extension, `yy` / `dd` / `p` / `uy` the shelf,
  `yn yp yd` names and paths, `D` trash, `dD` delete, `cw` / `A` / `I`
  rename, `/` `n` `N` search, `:` the command line, `gt gT gn gc` tabs,
  `o…` sorting, `zh` hidden files, `R` refresh, `?` the cheat sheet; on
  macOS also `⌃d ⌃u ⌃f ⌃b ⌃o ⌃i` (Ctrl is the command key elsewhere).
  Vim-only commands (`AppCommand.isVimOnly`) have no default chord, so the
  Hotkeys page lists them only with Vim keys on; two-key sequences are
  `Chord(prefix:)` and show their prefix in the footer while it waits.
- `VimKeys` (in `PanelView._onKey`, before the shortcuts) takes counts
  (`5j`, `3G`, `2gt`), the letter after `f F m '`, and Esc for what waits.
  Letters are commands in Normal mode and quick-search text only while the
  `/` prompt is open (`PanelTabState.searching`); Return keeps the matches
  for `n` / `N`, Esc clears them. Esc then steps back one thing at a time:
  the prompt, the matches, Visual mode, the selection (`gv` brings it back
  from `lastSelection`).
- Visual mode is `visualAnchor` + `visualBase` in the tab: the selection
  is the base plus the rows between the anchor and the cursor, recomputed
  in `moveCursorTo`; an operator (`yy`, `dd`, rename…) ends it and keeps
  the selection, as does `v` again; a new folder drops it.
- Vim's register is the shelf (see below): `yy` and `dd` put the
  targets in its place (`dd` marks them cut), `ys` adds to it, `p` puts
  its items into the active folder (the cut ones moved, and they leave;
  the others copied, and they stay), or pastes the clipboard's paths when
  it is empty; `uy` clears it. Marks persist in `Preferences.vimMarks` (letter → `Location.encode()`);
  `''` goes back in the history.
- The `:` line is `VimCommandLine` in the footer (↑ ↓ history, Tab
  completes command names and paths through `FileRepository.peek`),
  run by `_VimActions._runVimCommand`: `cd` (also `-`, `~`, relative),
  `mkdir`, `touch`, `rename`, `cp`, `mv`, `trash`, `delete`, `sort
  <field>[!]`, `set [no]hidden|foldersfirst|parent|tabs|vim[!]`, `tabnew`,
  `tabclose`/`q`, `tabnext`, `tabprevious`, `e`/`view`, `find`, `marks`,
  `refresh`, `sync`, `swap`, `help`, or a row number.
- Text fields inside the panels (`InlineRename`, the command line) sit in
  a `PanelTextGuard`: every plain panel-scope key (`j`, Space, Backspace,
  `/`, a prefix…) is `DoNothingAndStopPropagationTextIntent` there, so
  typing a name never moves the cursor or climbs a folder.
- `H M L` need the first visible row, which `RowsList` / `RowsBrief`
  report in `PanelGeometry.firstVisibleRow` on scroll; `zz zt zb` set
  `PanelTabState.scrollAlign`, honoured by the views' `_reveal`.

### Palette, jump, shelf and the names editor

Four ways around the window that share one picker. `AppQuickPicker`
(component library) is a search field over a list that builds the rows in
view only (one `rowExtentOf` per row, captions too): ↑ ↓ round the ends
(⌃P ⌃N), PageUp/PageDown, Home/End, Return picks with ⌘ or ⌥ for the
other actions (`AppQuickPickerAction`), Esc leaves; hovering lights a row,
the matched characters are bold, and empty and no-results texts stand in
for rows. `showAppQuickPicker` floats it below the window's top row with
no dimming and gives the focus back before the caller acts.

- Command palette (⌘P, `features/palette`). The app root handles
  `commandPalette` for every route, so it opens over the panels, the
  viewer or a dialog. It lists `commandsAt(focusedContext)`: the commands
  some `CommandHandlers` above the focused widget handles, the window's
  and that place's, never one nothing would run; Vim's only while Vim keys
  are on. With nothing typed: the commands run from it lately
  (`RecentItems` under `ferryx.recentCommands`), then every command by
  `CommandSection`; typing ranks by `fuzzyMatch` (a subsequence, best
  alignment by dynamic programming: word starts, the prefix and runs earn,
  gaps cost; ties to the more recent, then the shorter label) over the
  label and, in another language, the English label too, shown beside it
  when that is what matched. A pick closes the palette, waits for the
  frame in which the focus is back, and invokes a `CommandIntent` at the
  place it was: the handler chain runs it as its key would.
- Jump to Folder (⌘G, Vim `gj`, `:z words`). `PanelCubit.onFolderShown`
  counts each folder on disk the user goes to (not the tabs a start
  restores, nor a folder read again in place) into `FolderFrecency`:
  zoxide's rank (a point a visit, all ranks scaled down once their sum
  passes 10 000), weighted by the last visit (×4 within the hour, ×2 the
  day, ×½ the week, ×¼ after), at most 1 000 folders, the least frecent
  pruned, written under `ferryx.folderFrecency` at most once per 2 s and
  on dispose, never into the preferences blob. A query matches zoxide's
  way (every word in order, case aside; the last as far right as it goes,
  and folders whose own name holds it rank first), the panel's own folder
  left out. Rows show the name and the folder it is in as `~/…`. Return
  opens in the active panel, ⌘Return in a new tab, ⌥Return in the other
  panel; a folder gone from disk leaves the list with a notice. `:z
  words` goes straight to the best match.
- Shelf (Add to Shelf ⌥⌘S / `ys`, show ⌃⌘S / `gs` / `:shelf`). An
  ordered set of items (`Shelf` of `ShelfItem`: the row, a cut mark, a
  missing mark) in `WorkspaceState`, shared by both panels and the Vim
  keys above. Session only: paths gathered for the task at hand go stale
  once the app closes, and an operation must not run on a list nobody
  remembers making. `ShelfStrip` sits between the panels and the key
  hints (`AnimatedSize`, so the panels give it room smoothly, at once
  under reduced motion): the count, the items as fixed-width chips in a
  lazy row (icon, name, folder, cut mark, take-off button), Clear, and
  Copy Here / Move Here into the active panel's folder through the
  operations (items already there or gone from disk stay out; moved ones
  leave the shelf). It shows with the first item and goes with the last.
  The strip is an `AppFocusArea` with a cursor: ← → Home End, Return shows
  the item in the active panel, Delete or Backspace takes it off, Esc
  goes back, and the hint strip shows those keys meanwhile; ⌃⌘S focuses
  it, or hides it from inside. Missing items are found by `stat` after
  operations and directory changes (debounced), drawn faint, and say so.
- Rename in an Editor (⌃⇧M, `cn`, `:names`). The names of the selection,
  else of every row shown but `..` (editing names as lines is for many at
  once; one has rename in place), as monospace text one per line. The
  field never wraps (it is as wide as its longest line inside a sideways
  scroll), and beside it lazy columns of line numbers, the names now and
  the problems follow its scroll row for row (a forced strut keeps every
  line one row). `checkNames` (pure) reads the text: a line kept exactly
  renames nothing, another is trimmed; empty, a `/`, `.`/`..`, a name on
  two lines, a name of the folder not being renamed (hidden ones too, from
  `peek`), extra or missing lines are errors, marked by their lines and
  summed up under them with the caret's line's message. Rename (⌘Return;
  Return is a new line) runs `RenameService.apply` once for every change;
  the core stages swaps through temporary names and puts an item that
  cannot land back under its own name. Esc asks before edits are lost.

### The integrated terminal

Nimble Commander's terminal: the user's shell under the panels, in their
place, or over the whole window, in step with the active panel's folder.

- **Core** (`ferryx_term`). `Session::spawn` resolves the shell (the
  settings' path or a name on `PATH`, checked, else `$SHELL`, the passwd
  shell, `/bin/zsh`, `/bin/bash`; `pwsh`, PowerShell, `cmd` on Windows),
  runs it as a login shell (`-zsh` as its name) in the panel's folder with
  `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=Ferryx`, and
  `LANG` set from the system's language when the environment names no
  locale (an app started from the Dock has none). Three threads: the reader
  (our own non-blocking duplicate of the master, waited on in 100 ms
  slices so a closing session never hangs it; portable-pty's writer is not
  used, as dropping it types a newline and EOF), the writer (keystrokes in
  order), and the pump: chunks gathered into batches (one per 10 ms at
  most while bytes flow, 64 KiB each, an echo after a pause at once), sent
  while the listener has credit (two batches; `terminal_ack` gives one
  back). Without credit the pump stops reading, the bounded channel fills
  and the kernel's buffer stops the program, as a real terminal does. The
  shell's state (`idle`: the terminal's foreground process group is the
  shell's; `folder`: `proc_pidinfo(PROC_PIDVNODEPATHINFO)` on macOS,
  `/proc/<pid>/cwd` on Linux) is probed 40 ms after output stops and every
  400 ms, and sent when it changes; a folder the interface asked for is
  reported as it spelled it (`/tmp`, not `/private/tmp`). `change_directory`
  types ` cd -- '<folder>'` and Return only when the shell is idle and
  elsewhere (single quotes, a leading space for the history; a name with a
  control character is never typed). `close` hangs up the shell and its
  foreground job; the pump reaps it, SIGKILL after a second. Windows:
  ConPTY names no foreground process and another process's folder is only
  in its PEB, so both stay unknown and the folder is never synchronised.
- **Bridge** (`api/terminal.rs`). `terminal_start` answers an id;
  `terminal_events(id)` is the session's own stream; `terminal_write`,
  `terminal_resize`, `terminal_ack` and `terminal_state` are sync, so
  keystrokes keep their order (a write only queues them for the writer).
- **Emulation** (`features/terminal`). `TerminalSessionCubit` owns the
  xterm.dart `Terminal` (scrollback from the settings, 10 000 lines by
  default) and lives as long as the window, so hiding the terminal keeps
  the shell and its output. The shell starts the first time the terminal is
  shown, once the view has measured itself. Output is decoded across
  batches (a chunked UTF-8 decoder) and parsed at most 16 KiB per turn of
  the event loop, later events held back meanwhile, so frames keep coming
  in a flood (debug JIT: `yes | head -n 200000` in about 200 ms, the
  longest stall about 18 ms); the batch is acknowledged after it is parsed.
  Repaints are the render object's, once a frame. The theme's surface,
  text and accent (the cursor, translucent so the letter shows), the
  selection colours (emphasized where the keys are, grey elsewhere) and
  `AppTerminalColors` (sixteen ANSI colours per brightness) make its
  colours; the platform's monospace face its type at the settings' size
  (the interface's text scale does not apply: the terminal's size is its
  own setting), with Nerd Font faces as fallbacks for prompt icons. An
  exit or a failed start shows a line under the emulator; Return or its
  button starts a new shell below the old output, the modes a program
  left on reset.
- **Keys**. Every key goes to the shell but the terminal's own commands
  (`CommandScope.terminal`: copy, paste, select all, clear, scroll a page;
  ⌘C ⌘V ⌘A ⌘K ⇧PgUp ⇧PgDn, Ctrl+Shift+C/V/A/K elsewhere, where Ctrl+C is
  the shell's), its menu key, its place (`ShortcutMap.terminalPlacement`),
  and the window's chords no program in a terminal is given
  (`Chord.reachesWindowFromTerminal`: those with ⌘ on macOS, those with
  Ctrl+Shift elsewhere). ⌘K is "Connect to Server" in the window but
  clears inside the terminal, as in Terminal.app: the terminal's keys are
  matched first. ⌘ chords the window does not bind are swallowed, never
  typed. On Windows and Linux the terminal's places are Ctrl+\` (whole
  window), Ctrl+Shift+↑/↓ and Ctrl+Shift+\`, as Ctrl+Alt is AltGr there.
- **Folder sync** (`FolderSync`). Panel to shell: when the active panel
  (or which panel is active) changes and the terminal is on screen, `cd`
  is typed if the shell waits at its prompt with nothing typed on its line
  (the cubit watches what the user types: Return, ⌃C, ⌃U, ⌃D clear the
  line, a program ending leaves a fresh prompt); a hidden terminal follows
  when it is shown again; a folder inside an archive is never sent. Shell
  to panel: when the shell comes back to its prompt in another folder than
  at its last prompt, the active panel opens it. While a `cd` the terminal
  typed is under way (until the shell reports it, or two seconds), the
  shell's folders are not sent back, so a panel moving quickly is never
  pulled back; the panel moving while a program runs is not undone when it
  ends. Known limit: a line continued with PS2 counts as clean.
- **In the window** (`features/panels`). `TerminalDock` keeps the place
  (`TerminalPlace`: hidden, overlapped, panels hidden, full window) and
  the height in lines; the workspace lays the panels and the terminal out
  in one `Stack` (the panels are unmounted while hidden, so hint mode never
  labels them), with a vertical `AppSplitter` between them (drag, or ↑ ↓,
  0, Home/End, Return, Esc; the panels keep a header, four rows and the
  footer). ⌃` (or NC's ⌃⌥↑) shows the terminal and gives it the keys, and
  when it has them, makes it a line taller; ⌃⇧` (or ⌃⌥↓) hides it from
  anywhere and gives the panel the keys (⌃` and ⌃⇧` come first on macOS
  because window managers such as Rectangle take ⌃⌥↑ and ⌃⌥↓); ⌃⌥O hides the panels over it and brings them back; ⌥⌘O
  takes the whole window (no key hints, no operation cards) and goes back
  where it was. The place and the height are saved (debounced) and
  restored. The key hint strip shows the terminal's keys while it has
  them. Vim's `:term [command]` shows it and types the command at a clean
  prompt.

### Operations in the window

`OperationsService.progress` feeds the workspace: a card per operation
floats over the panels' corner with its title, progress, speed, time left,
pause and stop; a finished operation's card goes after a moment unless it
had errors. A question opens `showQuestionDialog` once (by its id) and
the answer goes back through the service; the panels refresh from the
core's directory events, never from the operation's end.

### The desktop's own services

Quick Look, the share picker and dragging files to and from other
applications are what some desktops have and others lack, so they reach
the window only through `PlatformServices`, created in
`composeDependencies` for the platform and handed to `WorkspaceScreen`
by `routing.dart`. Features read `capabilities`, never the platform; the
composition root turns a missing capability into unavailable commands
(`unavailableCommandsFor`), which `ShortcutMap.forUser(unavailable:)`
unbinds and `isAvailable` leaves out of the row menu, the cheat sheet,
the hotkeys and the palette. The panels' side is `native_actions.dart`
(a part of the workspace) over the pure `quick_look_pick.dart` and
`drop_plan.dart`.

- **Quick Look** (⌘Y; `preview` moved to ⇧⌘Y, Space keeps it):
  `NativeServices.swift` in the runner owns a `QLPreviewPanel` (the window
  is its controller in the responder chain) fed with file paths and an
  index. The panel is ordered front without taking the keys, so the
  panel's cursor keeps them: while it is open the workspace follows the
  active panel's cubit, sends `quickLook.select` when only the cursor
  moved (an index computed from the cursor, nothing per row) and the whole
  list again when the rows, the selection, the tab or the side changed.
  Several selected rows are shown as the list, else the folder's items
  without `..`. Inside an archive the focused file (or the selected
  files) is taken out first through `extractToTemp`, up to 64 MB a member,
  with a counter so a slow extraction never overtakes a later move. Space,
  Esc and ⌘Y close it (`PanelHooks.onEscape` before the panel's own Esc);
  when the user clicks the panel and it takes the keys, the runner sends ↑
  and ↓ back as `quickLook.step` and closes on Space, Esc and ⌘Y. Closing
  puts the focus back on the active panel.
- **Share** (⇧⌘S, the row menu's Share…, `:share`): the targets' URLs to
  `NSSharingServicePicker`, pointing at the cursor's row (keys) or where
  the menu opened (pointer), sent in Flutter's logical coordinates and
  turned into the view's own in Swift. Archive members are taken out
  first. Windows (`IDataTransferManagerInterop`) and Linux have none, so
  the command is hidden there.
- **Drag and drop.** Rows are `FileDragSource`s: a drag starts once the
  primary button has moved past the desktop's threshold (4 on macOS and
  Windows, 8 on GNOME), so clicks, ⇧-clicks and ⌘-clicks stay clicks; it
  takes the selection when the row is in it, else the row alone with the
  cursor moved there. The workspace builds a `FileDragRequest` (the paths,
  a `PanelDragPayload` map for drops in this window, a `FileDragImage`
  painted off screen: the icon with a count badge) and
  `SystemFileDrags` starts the desktop's session: one item per file for
  other applications, the picture on the first item only and a clear
  pixel on the others, the items registered together (1 000 files: about
  30 ms to register and 180 ms to start in a profile build, frames
  keep coming). Archive members travel as in-window data only (copy out).
  Drops land on `PlatformDropArea`, one `DropRegion` over the whole
  window, which hit-tests for the `FileDropTarget` under the pointer (a
  folder row or `..` over its panel) and asks it per move; another
  application's first file is read once per drag, every file on the drop.
  `planDrop` decides: into an archive or a folder into itself refused
  (the desktop's "not allowed"), the folder the items are in nothing, out
  of an archive an extraction, a key that forces an operation wins (the
  desktop leaves ⌥'s copy alone in the allowed set, and none for macOS's
  ⌘, a move), else one volume (`FileRepository.volumeOf`, the Rust
  `volume_id`, cached for the drag) moves and another copies. The spot
  lights up with the emphasized selection (`RowLook.dropTarget`) or the
  panel's `AppDropOutline`, and the drop starts an ordinary copy, move or
  extraction with its questions and progress card.

**Why super_drag_and_drop.** It is the one package that both drags files
out and takes them in, with the operation's feedback, on macOS, Windows
and Linux, and that tells a drag of this window from another
application's (local data); `desktop_drop` only takes drops in, with no
feedback, so drags out would need three native implementations of our own
(an `NSDraggingSource`, OLE `DoDragDrop` with `CF_HDROP`, a GTK source).
It builds Rust through its own copy of cargokit; `cargokit_options.yaml`
at the root opts into its signed precompiled binaries, so no developer or
CI machine compiles it (and no Homebrew `rustc` links it against the
host's macOS), while our crate, which publishes none, is still built by
`rust_builder/`. Under `flutter test` it runs on a mock context, so the
widget tests need no native library. The plugin stays inside
`platform_services`: features see `FileDragSource`, `FileDropTarget` and
the service.

## Operations stream: undo, compare and sync, checksums, duplicates

### Undo and redo (⌘Z, ⇧⌘Z; Vim `uu`, `U`; `:undo`, `:redo`)

The journal (`ferryx_ops::journal`) lives in the core, so every caller is
covered: the `Runner` owns it, and every operation records what it changed
through its `OpContext` (`record_created`, `record_moved`,
`record_overwritten`, `record`), whatever started it (a panel, a dialog,
the Vim register, a feature of another stream). Bridge calls that change
files themselves (inline and batch rename, new folder or file, links, a
saved checksum file) record through `tasks::record`. A step is a list of
`Change`s in the order they happened:

| Change | Undone by | The other way |
|---|---|---|
| `Created` (a copy, a new folder, an archive, an extraction) | moving it to the trash | putting it back |
| `Moved` (a move, a rename) | the move back (a rename, across volumes a copy and a delete) | the move again |
| `Trashed` (with the trash's receipt) | putting it back | trashing it again |
| `FolderRemoved` (a merge emptied it) | making it again | trashing it (empty) |
| `Overwritten` | nothing: its contents are gone | nothing |

Undoing walks the step last change first and records what it did as the
redo step (`Journal::finish_walk`); redo is the same walk over that.
Created items go to the trash, not away, so an undo loses nothing. A copy
records only the topmost item it made (what is inside needs no record of
its own); a merge records each item it made inside the folder that was
there; an item moved across volumes turns the copy's records into moves.
Names that swapped (a batch rename) go back through temporary names. A
step keeps up to 200 000 changes, beyond that it is on record as too big
to undo; the stack keeps 100 steps; a new step empties redo. Permanent
deletion is never recorded (its dialog says it cannot be brought back).

Before a walk, `undo::check` compares every change with the disk: an item
gone (`Missing`), a place taken (`Occupied`), an item no longer in the
trash, putting back not possible here; and as warnings an item changed
since (by its size and time) or overwritten (`Lost`). The panels ask
`OperationsService.checkStep`, then walk at once when nothing is in the
way, or show `UndoDialog` with each issue by path: "Undo the rest" or, when
nothing is left, "Forget Step". A walk is an operation (`OpKind.undo` /
`redo`) with a card titled by the step ("Undo Move of 3 items");
`OperationsService.journal` brings what undo and redo would do next
(`JournalChanged` events), and the panel menu names it or greys it.

The trash keeps a receipt per item (`ferryx_vfs::trash`): on macOS
`NSFileManager trashItemAtURL:resultingItemURL:` names the item's place in
the Trash and putting back is a rename (Finder's own Put Back does not know
such items); on Linux (the freedesktop trash) and Windows the `trash`
crate's listing finds the item by its original path and deletion time and
`restore_all` puts it back. Elsewhere `put_back_supported` is false and the
check says so.

### Compare Folders (⇧F2, `:compare`, `:compare!`)

Pure Dart over the listings the panels hold (`compareFolderEntries` in the
panels feature): a file or folder on one side only is selected there; of
two files of one name the newer (times within a second agree), both when
the times agree and the sizes do not; folders on both sides are left
alone; a file against a folder selects both. Names pair as the active
panel sorts them: exactly, then ignoring case unless the collation is
case-sensitive. With Settings → General → "Compare the contents of files
of the same size" (or `:compare!`), those files are compared byte for byte
in the core as an operation (`OpKind.compareContents`, a card with
progress and Stop); when it ends `takeContentDifferences` names the pairs
that differ and the panels add them to the selection, if they still show
the same folders.

### Synchronize Folders (⌥⇧F2, `:synchronize`; `:sync` stays Sync Panels)

`sync_feature`: the two folders (prefilled from the panels), the options
(subfolders, contents, two seconds of time tolerance for FAT, hidden
files, a mask for files, the direction and, one way only, deleting what
the source lacks), Compare. `ferryx_ops::sync::compare` walks both trees a
folder at a time, pairs names (exactly, then ignoring case; Unicode forms
are one name) and sends rows as it goes (`CompareProgress`, ≤ 500 rows or
80 ms an event): memory holds one folder of the walk; a hundred thousand
rows live in Dart as one append-only list with one byte of action each.
Each row starts with a suggested action (`defaultAction`: both ways what
is alone or newer crosses; one way the source wins, a newer file on the
target side is left for the user, deletions only with the option). The
table (`AppRowList`) is virtual: ↑ ↓ and ⇧ select, Space walks a row's
actions (several rows follow the first), → ← send rows to a side,
Backspace leaves them, a click on the action walks it, the menu offers
every action. Filters show left-only, right-only, newer, different,
identical rows, each with its count. Synchronize asks first (copies,
bytes, files replaced, items to the trash; destructive when deleting) and
runs `run_sync` as an operation: copies both ways through the copy runner
(attributes and verification as the preferences say), then deletions to
the trash; an item changed since the comparison is asked about, never
overwritten blindly. The step is undoable. The options are kept in
`Preferences.compareOptions`.

### Checksums (⌃⌘H, `:checksum [sha256|sha1|md5|blake3]`)

`checksums_feature`: the targets (folders walked, optionally into
subfolders) are listed first, then hashed on a few workers
(`hashing::parallel`, 1 MiB buffers, cancellable) as `ChecksumProgress`
events; the table shows the hash in monospace, a pasted expected hash
lights its row, ⌘C copies the selected hashes, "Save Checksum File…"
writes the GNU form (`hash  name`, names relative to the folder, escaped
when they hold a backslash or a line break) and is undoable. A single
checksum file (`*.sha256`, `SHA256SUMS`, `*.md5`, `*.b3`…, GNU and BSD
lines) is checked instead: OK, mismatch, missing, with a summary.

### Find Duplicates (⇧⌘F, `:dupes`)

`duplicates_feature`: the active folder (and the other panel's on
request), a minimum size, a mask, hidden files. `ferryx_ops::duplicates`
walks without following links, keeps sizes seen twice, folds hard links to
one inode (and overlapping folders) into one file, then settles the
candidates a chunk at a time, the largest first: the first 16 KB hashed,
what still matches hashed whole (BLAKE3), each group sent as it is
settled. Rows are grouped (size × copies, space to free); Space marks,
"Mark" keeps the newest, the oldest or the shortest path of each group;
Move to Trash goes through the operations runner, so ⌘Z puts the files
back; a group with every copy marked is warned about.

## Network locations

A panel's tab can be a folder on a server: SFTP, FTP and FTPS (explicit
TLS, `AUTH TLS` and `PROT P`), WebDAV over HTTP and HTTPS. Connect to
Server (⌘K; in the terminal ⌘K stays Clear) takes an address
(`sftp://user@host:port/folder`, `ftp://`, `ftps://`, `dav://`, `davs://`,
`http://`, `https://`) or a saved server (name, protocol, host, port,
user, start folder, how SFTP logs in); Go To (F1/F2) lists the saved
servers, Go to Folder and `:connect`/`:cd` take an address, Disconnect
(the panel menu, `:disconnect`) closes the active tab's server.

### Crates

Pure Rust, no OpenSSL and no libssh2; `ring` is the one C and assembly
dependency (rustls's and russh's crypto), built by cargo for every target.

| Crate | Why | Licence |
|-------|-----|---------|
| `russh` 0.63, `russh-sftp` 2 | SSH and SFTP v3 in Rust (the client side of Warp's and many servers'), async on tokio; `ring` and `rsa` features only, so no aws-lc. Maintained, frequent releases. | Apache-2.0 |
| `suppaftp` 6.3 | FTP and explicit FTPS, sync API, rustls through `RustlsConnector`; `MLSD`/`MLST`/`FEAT`. The sync API is wrapped so a stop cuts it short (`remote::blocking`). | MIT or Apache-2.0 |
| `reqwest` 0.12, `quick-xml` 0.38 | WebDAV's HTTP (streamed bodies, rustls, no native-tls) and its `PROPFIND` XML. | MIT or Apache-2.0; MIT |
| `rustls` 0.23 + `rustls-platform-verifier` 0.6 | TLS for FTPS and HTTPS, certificates checked against the system's roots and policy (Keychain, CryptoAPI, the distribution's store). | Apache-2.0, ISC or MIT |
| `keyring` 3.6 | Passwords in the macOS Keychain, Windows Credential Manager, the Secret Service (pure-Rust `zbus`, no libdbus). | MIT or Apache-2.0 |
| `tokio` 1 | The runtime of russh and reqwest: two workers owned by the core (`remote::runtime`). | MIT |
| `dav-server`, `rcgen`, `hyper` (tests only) | The in-process WebDAV server and the test certificate authority. | Apache-2.0; MIT or Apache-2.0 |

The workspace MSRV (1.85) still builds: the new dependencies were chosen
with `CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback`.

### Locations and keys

`Location.remote(server:, path:)`: `server` is the server's key,
`scheme://user@host:port` (the user percent-encoded, the port always
there), made by the core (`server_key`, `parse_server_address`), never
by Dart, so both sides agree on it; `path` is absolute on the server. It
saves as `remote:<key>#<path>`, shows as `sftp://user@host/path`
(`Location.display`), its root crumb as `user@host` with the server's
icon. Native-only features check the location: a command that works on
this computer alone says so (`networkNotOnServer`) or is hidden from the
row and panel menus. A folder on a server never reaches the terminal (it
does not follow), Jump to Folder (not counted) or the undo journal
(network operations run with `Journaling::Off`).

### The core (`ferryx_vfs::remote`)

- `RemoteFs` is the one trait (list, stat, byte ranges, streamed reads and
  writes with a `Stop`, mkdir, rename, delete, set a file's time where the
  protocol can, a server-side copy for WebDAV, reconnect, close, reap
  idle): `SftpFs` (one SSH connection with one SFTP session that every
  call shares; 16 requests of 64 KiB in flight both ways; keepalive every
  30 s), `FtpFs` (a pool of up to 3 control connections, one transfer
  each; idle ones closed after a minute; `MLSD`, else `LIST` read as Unix,
  DOS or MLSx lines; passive mode with the NAT workaround, `EPSV` over
  IPv6), `DavFs` (`PROPFIND` depth 1, ranged `GET`, streamed `PUT`,
  `MKCOL`, `MOVE`/`COPY` without overwrite, `DELETE`).
- `connection` keeps the servers open by key; one connection attempt per
  key at a time; a server is `Connected`, `Lost` (the next call opens it
  again with the credentials kept for the run, no question) or `Closed`;
  the changes go out as `ConnectionChanged` events. A reaper closes idle
  FTP connections.
- Every wait has a deadline (connect 20 s, a request 30 s) and a `Stop`
  asked every 40–50 ms, so a cancel ends it at once: async calls through
  `runtime::run`; FTP's blocking calls through `blocking` (connection
  attempts on a thread of their own, a call watched by a thread that
  shuts its socket on a stop, data sockets read in 50 ms slices); SFTP
  requests fail as soon as the SSH connection ends instead of at their
  deadline.
- Errors are `VfsError` kinds the interface words (`AuthFailed`,
  `HostUnreachable`, `TimedOut`, `HostKeyUnknown`, `HostKeyChanged`,
  `ConnectionLost`, `NotConnected`, `CertificateInvalid`, and the file
  kinds); the message carries the detail only (the server, the path, the
  known_hosts line).

### Security

- Host keys are checked against `~/.ssh/known_hosts` and Ferryx's own
  file (`~/Library/Application Support/Ferryx/known_hosts`,
  `%APPDATA%\Ferryx\known_hosts`, `$XDG_CONFIG_HOME/ferryx/known_hosts`):
  hashed names, `[host]:port`, patterns and negations; a `@revoked` key is
  refused, `@cert-authority` lines are left aside (host certificates are
  not checked against them). An unknown key asks the
  user with its SHA256 fingerprint (Return is Cancel, never Trust); a
  trusted one may be remembered in Ferryx's file only. A changed or
  revoked key is refused before any password goes out, with an alarm that
  names the known_hosts line and offers no way past it: the old line must
  be removed by hand.
- Passwords and key passphrases go to the system keychain (service
  `Ferryx`; the account is the server key, or `passphrase:<key path>`)
  only when the user ticks Remember; a refused one kept there is asked
  again and replaced. They never go into the preferences (a saved server
  has no password field; recent addresses are kept without one), the
  logs or an event; a password typed into an address is used once. For
  the run, a connection keeps its password in memory to log in again
  after a drop.
- SFTP logs in as OpenSSH does: the agent's keys (`SSH_AUTH_SOCK`, the
  OpenSSH agent's pipe on Windows), the default key files (a passphrase
  asked), the server's prompts (keyboard-interactive), a password.
- FTPS and HTTPS verify certificates with the system's roots; a failure is
  `CertificateInvalid`, never a prompt to accept. Plain FTP and HTTP work
  but say they are not encrypted: a note in Connect to Server and the
  editor, an open lock in an orange capsule in the panel's footer.

### Listings, questions, operations

- `open_listing` reads a server's folder like a disk's (sorted in the
  core, the `..` row, hidden items filtered); nothing watches it: a panel
  reads it again on ⌘R, after an operation that touched the server, and
  on Reconnect. A newer read of a tab replaces an older one still waiting
  (`Cancelled`, which the panel ignores). A tab restored on a server at
  start waits, not connected, with Reconnect in its error strip and its
  footer: nothing asks for a password at start. Going to a server that is
  not connected connects first (with its saved way of logging in); a
  disconnected server sends its tabs back to their last folder on disk.
- A connection's questions (`NetworkQuestion` events: host key, password,
  passphrase, the server's prompts) wait in the core for
  `answer_network_question`; `NetworkPromptHost` shows them one at a time.
  A question its connection gave up on (cancelled, disconnected) is
  withdrawn (`NetworkQuestionWithdrawn`) and its dialog closes.
- `start_network_operation` runs `ferryx_ops::transfer` as an operation
  with its card, pause, cancel and questions: copy and move between the
  disk and a server or two servers (streams, no temporary file; a file cut
  short is removed; modification times kept where the protocol can set
  them: SFTP, FTP with `MFMT`), a move within one server is a rename, a
  copy within WebDAV is the server's own; delete (a server has no trash:
  F8 always asks, and says so); folder sizes. Its sources and destination
  are named `<server key><path>`, so a panel knows which of its tabs to
  read again.
- Opening a file on a server (Return, Open) copies it to a temporary
  folder of its own and opens that copy; a notice says that changes stay
  in the copy (nothing is sent back). F3 reads byte ranges from the
  server.

What works on a server: browsing, the viewer, open (a copy), copy, move,
rename, new folder and file, delete, folder sizes, Compare Folders (by
names, sizes and dates), drag and drop between the panels, favorites and
marks. What does not (a notice says so): the terminal, Quick Look, Share,
Open With, Show in Finder, the trash, attributes, links, compress and
extract, checksums, duplicates, synchronize, flat view, Finder tags,
batch rename and the names editor, the shelf, Find Files.

## Start-up

`main.dart` → `starter()` (error zone, bloc observer; `configureWindow()`
picks the `WindowFrame`) → `AppBootstrap` → `composeDependencies()` (bridge
init, preferences, the file repository and the services) → `AppScopes` →
`FerryxApp` (router, theme, locale, global shortcuts); `showWindow` then
shows the window and `WindowStateSaver` starts. A failure shows
`InitializationFailedScreen` with retry; the `ResourceDisposer` rolls back
partially created resources.

## Tests

- Rust: unit tests per crate; `ferryx_api/tests/api_flow.rs` runs the
  bridge end to end, `archives_flow.rs`, `flat_flow.rs` and
  `tags_flow.rs` the archives' passwords and Extract To, flat views and
  Finder tags. The archive tests write every format they read (a stored
  RAR5 and an ISO with Joliet names by hand); ignored tests time large
  archives, a flat walk of a big tree (`FERRYX_FLAT_BENCH=~/Library`), tag
  reading and a live Spotlight search.
- Dart: cubit tests (`bloc_test`, `mocktail`) in the panels, viewer,
  find and terminal features; widget tests in the settings feature, the
  component library and the terminal (its keys on macOS and Linux, the end
  notice, the menu) and the workspace with a fake terminal (its places,
  focus, height, folder sync, `:term`); unit tests in shortcuts,
  preferences_service, monitoring and `FolderSync`; a flood test (200 000
  lines through the cubit); `terminal_service` runs a real `/bin/sh`
  through the host library (`make core`). `workspace_native_test` drives
  the window against `FakePlatformServices` (Quick Look following the
  cursor, Share's anchor, drags past the threshold, drops planned and
  started); `drop_plan_test` and `quick_look_pick_test` cover the pure
  rules; `platform_services_test` the channel both ways.
  The panels' `panel_view_vim_test` drives a panel with simulated keys
  through the real shortcut map (`5j`, `v`, `/`, `:`, `f`, marks, the
  register hooks), `vim_keys_test` the count and pending-key parser.
  `test/support/workspace_harness.dart` pumps the whole window over
  folders in memory; the jump, shelf and names-editor tests drive it with
  keys. The palette's tests run a command from it through a real chain;
  `app_quick_picker_test` covers the picker's keys and virtualization.
- `test/app/` keeps the code to its rules: no Mac glyph or key name in a
  literal (`key_labels_test`), no hairline drawn by Flutter's own borders
  (`hairline_sources_test`), no method or function that builds widgets
  (`widget_helpers_test`), the window frame per platform
  (`window_frame_test`), the window's place on the screens
  (`window_state_test`).
- Operations stream: `ferryx_api/tests/operations_flow.rs` runs move →
  undo → redo, copy and trash undone through the trash (where the desktop
  can put back), renames with swaps, a taken place reported before undo,
  a comparison and a synchronization, content pairs, checksums with a
  check, duplicates; unit tests sit with `journal`, `undo`, `sync`,
  `checksum`, `duplicates`, `hashing` and `trash`. Dart: cubit and widget
  tests in the sync, checksums and duplicates features (the table's keys),
  `folder_compare_test` and `undo_dialog_test` in the panels,
  `app_row_list_test` in the component library.
- Network: `cargo run -p ferryx_test_servers --bin serve` runs the
  three test servers on 127.0.0.1 over folders of a few files (user `me`,
  password `secret`) and prints the FTP commands it gets, to try the
  network locations by hand.
- Network: in-process servers (`ferryx_test_servers`: russh's server with
  russh-sftp's handler, an FTP server of its own with `MLSD` on or off,
  explicit TLS and connections cut or hung after so many bytes,
  dav-server over hyper with Basic auth and TLS from an rcgen CA), so no
  test needs a network. `ferryx_vfs/tests/remote_*.rs`: host keys
  unknown, trusted, remembered, changed (refused without a question),
  wrong passwords asked again and kept in a keychain stand-in, key files
  with and without a passphrase, keyboard-interactive, certificates not
  trusted, names in many scripts, a server without `MLSD`, a connection
  dropped mid-read (reconnected after), a stop during a silent greeting
  and a hung transfer (ended within a poll), 10 000 items listed (≈60 ms
  over SFTP and FTP, ≈110 ms over WebDAV on loopback);
  `ferryx_ops/tests/transfer_flow.rs`: a tree both ways with its times,
  server to server and moves, conflicts, a drop mid-copy tried again, a
  cancel that takes the part away, deletes and sizes, a WebDAV copy made
  on the server; `ferryx_api/tests/network_flow.rs`
  the bridge end to end. Dart: `ConnectCubit`, the dialogs and the prompt
  host (Return never trusts a key; a withdrawn question closes), the
  panel on a server (`network_panel_test`, `network_panel_view_test`:
  waiting at start, Reconnect, given up quietly, a replaced read, a
  disconnect, refresh after an operation, sizes, rename), the drop rules,
  the bridge mapping, and `network_service` against the host library
  (addresses, keys, an unreachable port, a cancel).

## Known gaps

- No extended-attributes or process-list virtual file systems; archives
  are read-only, and a rar set of several volumes lists its first
  volume's members only.
- Servers: a file opened from a server is a copy (edits are not sent
  back); nothing on a server is undone; no flat view, Find Files,
  checksums or synchronize there; WebDAV logs in with Basic auth only (no
  Digest, NTLM or OAuth) and keeps no modification times; FTP's viewer
  opens a transfer per window it reads; SFTP's agent on Windows is the
  OpenSSH agent's pipe only (not Pageant); no SSH jump hosts, no
  `~/.ssh/config` aliases, no client certificates for FTPS or HTTPS; the
  panels poll no server for changes (⌘R reads again).
- The terminal: one session per window; no search in its scrollback;
  NC's "paste the file name into the terminal" (⌃⌥↩) is not there yet; on
  Windows the folder is not synchronised (see above).
- Finder tags have no list column of their own yet (the dots and the
  tip carry them); a flat view sees changes deeper than its folder made
  by other programs only on ⌘R.
- Scroll-only keys (⌥Home, ⌥End, ⌥PgUp, ⌥PgDn) move the cursor as the plain
  keys do.
- The clipboard carries paths as text (⌘C / ⌘V / ⌥⌘V). An archive's
  members drag only within the window (no file promises to other
  applications yet). On Windows a drop follows the volumes, not Ctrl and
  Shift, which super_drag_and_drop does not report; Quick Look and Share
  are macOS's alone.
- External editors and tools run through the desktop (`open -a`), not
  in the integrated terminal, even those marked "in terminal".
- Windows and Linux are built and tested in CI, not used on a desktop day
  to day; the macOS app is signed ad hoc, not notarised.
- Undo cannot bring back what was overwritten (it is reported, and left
  as it is) or deleted for good; the journal lives as long as the app.
  Items Ferryx trashes on macOS have no Finder Put Back.
- Compare Folders pairs names in Dart without Unicode normalization (a
  composed and a decomposed name differ there; Synchronize Folders folds
  them). Hard links are folded into one file by inode on Unix only.
