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
| `ferryx_api` | `flutter_rust_bridge` surface. Holds the open listings (`app.rs`: one per panel tab, with its raw rows for resorting and its watcher), the archive indexes, the operations runner (whose listener forwards progress as events) and the searches; converts to plain DTOs (`api/types.rs`, `…View` types, enums without payloads so Dart sees enums, `i64` counts so Dart sees `int`). Its `Cargo.toml` uses literal fields because cargokit parses it without workspace inheritance. |

The Operations stream adds to `ferryx_ops` the undo journal (`journal`,
`undo`), folder comparison and synchronization (`sync`), checksums
(`checksum`, `hashing`) and duplicates (`duplicates`); to `ferryx_vfs` the
trash with receipts (`trash`); to `ferryx_api` the files `journal.rs`,
`sync.rs`, `checksum.rs`, `duplicates.rs` and `tasks.rs` (ids, cancel
flags and event batching of the dialogs' work). `Runner::start_job` runs a
module's own job as an operation, with how its changes go on record
(`Journaling`). See "Operations stream" below.

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

Tests: `cargo test --workspace`. `ferryx_api/tests/api_flow.rs` runs the
bridge end to end (listings, resorting, the watcher's event, archives,
operations with a question answered, folder sizes, batch rename, find);
the tests take turns on the process-wide state.

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
| `shortcuts` | `AppCommand` (scopes: global, panel, viewer, lists, dialogs), `Chord`, `ShortcutMap` (defaults per desktop, `forUser` with overrides), the `CommandHandlers` dispatch chain, `ChordCodec`. |
| `preferences_service` | Installation preferences (theme, locale, text scale, shortcut overrides, window frame, the panels' state, layouts, sorting defaults, quick search, favorites, editors, tools, confirmations, copy defaults, viewer) + `PreferencesScope` and `PreferenceBuilder`. |
| `file_repository` | `FileRepository`: listings (open, refresh, resort, close, peek), items (stat, byte ranges, extract to temp, make, rename, links, resolve), the system (volumes, standard folders, free space, open, open with, reveal, eject, applications), attributes; `directoryChanges` names listings whose folders changed. |
| `operations_service` | `OperationsService` (start, pause, resume, cancel, answer, forget; `progress` stream and the latest report per operation; `run` waits for one), `FindService` (start, cancel, `updates`), `RenameService` (preview, apply). |
| `ferryx_localizations` | ARB-generated `FerryxLocalizations`, command and scope labels, formatting helpers (sizes, dates, durations, error titles, operation titles, answers, columns). |
| `component_library` | Tokens, the platform-adaptive theme and the desktop widgets (see Native look). |
| `features/panels` | The main window (`WorkspaceScreen`): two `PanelView`s with a `PanelCubit` each, the edge between them, the operations cards, every file command (`workspace_actions.dart`), the row and panel menus, and the dialogs: copy / move / copy as / move as, new folder, delete, compress, select by mask, go to folder, links, favorites, the Go To pop-up and the quick lists, batch rename, file attributes, and the questions of operations. |
| `features/viewer` | The built-in viewer (`ViewerScreen`): text, hex and preview over a `ViewerSource` (a file on disk or an archive member), windows of large files, find and go to. |
| `features/find` | Find Files (`showFindDialog`, `FindCubit`): the form, the streaming results, go to a hit or view it. |
| `features/settings` | The settings window (`SettingsScreen`: General, Panels, Viewer, Hotkeys, Editors, Tools, About) and the cheat sheet (`showCheatSheet`). |
| `features/sync` | Synchronize Folders (`showSyncDialog`, `SyncCubit`): two trees compared in the core, a virtual table with an action per row, the synchronization as an operation. |
| `features/checksums` | Checksums (`showChecksumsDialog`, `ChecksumsCubit`): hashes of files or the check of a checksum file. |
| `features/duplicates` | Find Duplicates (`showDuplicatesDialog`, `DuplicatesCubit`): groups of identical files, marks, Move to Trash. |

### Feature wiring

`routing.dart` → `Screen` → `Cubit` → `View`. Dependencies are injected at
`routing.dart`; the workspace is given a `WorkspaceNavigation` whose
callbacks open the viewer route, the find dialog, the settings route and
the cheat sheet, so the panels feature never imports those features. The
workspace reports its state (`WorkspaceSnapshot`: both panels' tabs, the
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

### Operations in the window

`OperationsService.progress` feeds the workspace: a card per operation
floats over the panels' corner with its title, progress, speed, time left,
pause and stop; a finished operation's card goes after a moment unless it
had errors. A question opens `showQuestionDialog` once (by its id) and
the answer goes back through the service; the panels refresh from the
core's directory events, never from the operation's end.

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
- Dart: cubit tests (`bloc_test`, `mocktail`) in the panels, viewer and
  find features; widget tests in the settings feature and the component
  library; unit tests in shortcuts, preferences_service and monitoring.
  The panels' `panel_view_vim_test` drives a panel with simulated keys
  through the real shortcut map (`5j`, `v`, `/`, `:`, `f`, marks, the
  register hooks), `vim_keys_test` the count and pending-key parser.
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

## Known gaps

- No integrated terminal yet, no SFTP/FTP/WebDAV, no extended-attributes
  or process-list virtual file systems; archives are read-only (zip, jar,
  tar, tar.gz); no Quick Look (the viewer's preview shows images).
- Finder tags are not read; the tag palette is in place for them.
- Scroll-only keys (⌥Home, ⌥End, ⌥PgUp, ⌥PgDn) move the cursor as the plain
  keys do.
- Drag and drop between the panels and with other applications is not
  wired; the clipboard carries paths as text (⌘C / ⌘V / ⌥⌘V).
- External editors and tools run through the desktop (`open -a`), not
  in a terminal.
- Windows and Linux are built and tested in CI, not used on a desktop day
  to day; the macOS app is signed ad hoc, not notarised.
- Undo cannot bring back what was overwritten (it is reported, and left
  as it is) or deleted for good; the journal lives as long as the app.
  Items Ferryx trashes on macOS have no Finder Put Back.
- Compare Folders pairs names in Dart without Unicode normalization (a
  composed and a decomposed name differ there; Synchronize Folders folds
  them). Hard links are folded into one file by inode on Unix only.
