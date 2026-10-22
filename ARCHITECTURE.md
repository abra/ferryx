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
file icons (`AppIcons`) and the tag palette (`AppColorsExt.ink/wash` by
index).

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
| `ferryx_vfs` | The file system: a folder's rows with their metadata (size, times, the macOS added time through `getattrlist`, mode, owner and group names, BSD flags, hidden), one entry, byte ranges of a file (`native`); archives as read-only folders (`archive`: zip, jar, tar, tar.gz; an index per archive read once and again when the file changed, members extracted to a temporary folder for opening); a folder watched for changes reported once per burst (`watch`, `notify`); the volumes (`volumes`, `sysinfo`) and the free space; the standard folders, opening with the desktop or an application, revealing in the file manager, the trash, ejecting (`system`); permissions, flags, owners and times read and written (`attrs`); symbolic and hard links (`links`). Every error is a `VfsError` with a kind the interface words. |
| `ferryx_ops` | Operations on threads with progress, pause, cancellation and questions: copy and move (a rename on the same volume, else a copy and a delete; folders merge; conflicts ask or follow the policy; attributes preserved; optional verification), duplicate (`name copy.ext`), extract out of an archive, delete and trash, compress to zip (deflate, optional AES-256), folder sizes, plus Find Files (`find`: name, contents in overlapping windows, size, streamed hits) and the application of a batch rename (`rename`: staged through temporary names when names swap). `Runner` holds every operation; `OpContext` is what an operation checks, reports and asks through. |
| `ferryx_term` | The integrated terminal's shell: a `Session` runs the user's shell as a login shell in a pseudo-terminal (`portable-pty`: openpty, ConPTY on Windows), sends its output in batches with flow control, probes whether it waits at its prompt (`tcgetpgrp`) and its folder (`proc_pidinfo`, `/proc/<pid>/cwd`), types `cd` when asked, and hangs up and reaps it on close. No emulation: that is the interface's. |
| `ferryx_api` | `flutter_rust_bridge` surface. Holds the open listings (`app.rs`: one per panel tab, with its raw rows for resorting and its watcher), the archive indexes, the operations runner (whose listener forwards progress as events) and the searches; converts to plain DTOs (`api/types.rs`, `…View` types, enums without payloads so Dart sees enums, `i64` counts so Dart sees `int`). Its `Cargo.toml` uses literal fields because cargokit parses it without workspace inheritance. |

Rules:

- A panel's listing lives in Rust while the panel shows it
  (`open_listing(listing_id, location, options)`): the rows are read once,
  sorted there, and resorted from the cache (`resort_listing`) without
  reading the disk again; a change of hidden items reads again. The
  folder is watched and `DirectoryChanged` names the listing; the panel
  then calls `refresh_listing`, keeping its cursor and selection by name.
- Locations are native paths or `(archive, inner path)`; a listing inside
  an archive comes from the archive's index and is not watched (the
  archive's folder is).
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

- A terminal session's output, state and end come on a stream of its own
  (`terminal_events`), not the app's event stream: they are high-volume
  and flow-controlled (see "The integrated terminal").

Tests: `cargo test --workspace`. `ferryx_api/tests/api_flow.rs` runs the
bridge end to end (listings, resorting, the watcher's event, archives,
operations with a question answered, folder sizes, batch rename, find);
the tests take turns on the process-wide state. `terminal_flow.rs` runs a
`/bin/sh` session through the bridge.

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
| `domain_models` | Pure Dart contracts: `FileEntry`, `Listing`, `Location`, `SortOptions`, `ListingOptions`, `Volume`, `StandardFolders`, `OperationRequest`/`OperationProgress`/`OperationQuestion`, `FindRequest`/`FindHit`/`FindUpdate`, `RenameOptions`/`RenameOutcome`, `FileAttributes`/`AttributeChanges`, `Favorite`, `PanelLayout`, `ExternalEditor`/`ExternalTool`, `FerryxException`. |
| `ferryx_backend` | The generated bridge, `FerryxBackend` (init, the event stream, `guard`) and `mapping.dart`. |
| `monitoring` | `Logger` and the console observer. |
| `shortcuts` | `AppCommand` (scopes: global, panel, viewer, lists, dialogs, terminal), `Chord`, `ShortcutMap` (defaults per desktop, `forUser` with overrides), the `CommandHandlers` dispatch chain, `ChordCodec`. |
| `preferences_service` | Installation preferences (theme, locale, text scale, shortcut overrides, window frame, the panels' state, layouts, sorting defaults, quick search, favorites, editors, tools, confirmations, copy defaults, viewer, the terminal's settings and place) + `PreferencesScope` and `PreferenceBuilder`. |
| `file_repository` | `FileRepository`: listings (open, refresh, resort, close, peek), items (stat, byte ranges, extract to temp, make, rename, links, resolve), the system (volumes, standard folders, free space, open, open with, reveal, eject, applications), attributes; `directoryChanges` names listings whose folders changed. |
| `operations_service` | `OperationsService` (start, pause, resume, cancel, answer, forget; `progress` stream and the latest report per operation; `run` waits for one), `FindService` (start, cancel, `updates`), `RenameService` (preview, apply). |
| `terminal_service` | `TerminalService.start` → a `TerminalSession` (its `updates`: `TerminalOutput`, `TerminalShellState`, `TerminalExited`; write, resize, ack, state, change directory, close) over `ferryx_api`'s terminal; the default shell's name. |
| `ferryx_localizations` | ARB-generated `FerryxLocalizations`, command and scope labels, formatting helpers (sizes, dates, durations, error titles, operation titles, answers, columns). |
| `component_library` | Tokens, the platform-adaptive theme and the desktop widgets (see Native look). |
| `features/panels` | The main window (`WorkspaceScreen`): two `PanelView`s with a `PanelCubit` each, the edge between them, the integrated terminal's place (`TerminalDock`, the view injected as a `WorkspaceTerminal`), the operations cards, every file command (`workspace_actions.dart`), the row and panel menus, and the dialogs: copy / move / copy as / move as, new folder, delete, compress, select by mask, go to folder, links, favorites, the Go To pop-up and the quick lists, batch rename, file attributes, and the questions of operations. |
| `features/viewer` | The built-in viewer (`ViewerScreen`): text, hex and preview over a `ViewerSource` (a file on disk or an archive member), windows of large files, find and go to. |
| `features/find` | Find Files (`showFindDialog`, `FindCubit`): the form, the streaming results, go to a hit or view it. |
| `features/settings` | The settings window (`SettingsScreen`: General, Panels, Viewer, Terminal, Hotkeys, Editors, Tools, About) and the cheat sheet (`showCheatSheet`). |
| `features/terminal` | The integrated terminal: `TerminalSessionCubit` (the session, the xterm.dart emulator it writes into, `FolderSync`), `TerminalPane` (its bar, the emulator in the theme's colours, the end notice, the menu) and `TerminalKeys` (which keys are the window's). |

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
  select, `*` / `#` by extension, `yy` / `dd` / `p` / `uy` the register,
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
- The register (`WorkspaceState.register`, a `VimRegister` of native
  paths with a move flag) is shared by both panels: `p` copies or moves
  them into the active folder (a cut register empties, a yank stays), or
  pastes the clipboard's paths when it is empty; the footer shows "3 cut".
  Marks persist in `Preferences.vimMarks` (letter → `Location.encode()`);
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
  footer). ⌃⌥↑ shows the terminal and gives it the keys, and when it has
  them, makes it a line taller; ⌃⌥↓ hides it from anywhere and gives the
  panel the keys; ⌃⌥O hides the panels over it and brings them back; ⌥⌘O
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
  bridge end to end.
- Dart: cubit tests (`bloc_test`, `mocktail`) in the panels, viewer,
  find and terminal features; widget tests in the settings feature, the
  component library and the terminal (its keys on macOS and Linux, the end
  notice, the menu) and the workspace with a fake terminal (its places,
  focus, height, folder sync, `:term`); unit tests in shortcuts,
  preferences_service, monitoring and `FolderSync`; a flood test (200 000
  lines through the cubit); `terminal_service` runs a real `/bin/sh`
  through the host library (`make core`).
  The panels' `panel_view_vim_test` drives a panel with simulated keys
  through the real shortcut map (`5j`, `v`, `/`, `:`, `f`, marks, the
  register hooks), `vim_keys_test` the count and pending-key parser.
- `test/app/` keeps the code to its rules: no Mac glyph or key name in a
  literal (`key_labels_test`), no hairline drawn by Flutter's own borders
  (`hairline_sources_test`), no method or function that builds widgets
  (`widget_helpers_test`), the window frame per platform
  (`window_frame_test`), the window's place on the screens
  (`window_state_test`).

## Known gaps

- No SFTP/FTP/WebDAV, no extended-attributes or process-list virtual file
  systems; archives are read-only (zip, jar, tar, tar.gz); no Quick Look
  (the viewer's preview shows images).
- The terminal: one session per window; no search in its scrollback;
  NC's "paste the file name into the terminal" (⌃⌥↩) is not there yet; on
  Windows the folder is not synchronised (see above).
- Finder tags are not read; the tag palette is in place for them.
- Scroll-only keys (⌥Home, ⌥End, ⌥PgUp, ⌥PgDn) move the cursor as the plain
  keys do.
- Drag and drop between the panels and with other applications is not
  wired; the clipboard carries paths as text (⌘C / ⌘V / ⌥⌘V).
- External editors and tools run through the desktop (`open -a`), not
  in the integrated terminal, even those marked "in terminal".
- Windows and Linux are built and tested in CI, not used on a desktop day
  to day; the macOS app is signed ad hoc, not notarised.
