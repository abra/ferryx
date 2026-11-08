<p align="center"><img src="brand/ferryx-256.png" width="128" height="128" alt="Ferryx"></p>

# Ferryx

A dual-pane file manager for the desktop, built for the keyboard: the
orthodox two-panel workflow of the classic commanders with the look and
manners of each desktop. The interface is Flutter; everything that touches
files is Rust.

![Ferryx on macOS with two file panels, folder tabs, sorting controls and contextual keyboard hints](docs/screenshots/ferryx-macos.png)

- **Two panels** with tabs (⌘T), each with its own history (⌘[ / ⌘]),
  sorting and view mode; swap (⌘U) and sync (⌥⌘U) them, or collapse to one
  (⇧⌘P). The edge between them moves by drag or by the keys (⌥⌘\).
- **Cursor and selection kept apart**, as orthodox managers have them:
  the arrows move the cursor, ⇧ with them selects, Insert / ⌥Space toggles
  a row, ⌘A / ⌥⌘A / ⌃⌘A select all, none, or invert, ⌘= selects by a mask
  or a regular expression.
- **Quick search**: type a few letters and the matching names are
  underlined (fuzzy, anywhere, at the beginning or the end; optionally only
  the matches show). Esc clears.
- **View modes**: Brief (names in columns) and List (a table of columns);
  five presets on ⌃1–⌃5, editable in Settings.
- **Sorting** by name, extension, size and the modified, created, added and
  accessed times (⌃⌘1–⌃⌘7), folders first or not, natural, case-insensitive
  or case-sensitive comparison; the panel header shows the sort field and
  direction, with a compact icon and full tooltip in narrow panels.
- **Operations in the background** with progress, speed and time left,
  pause and stop, and questions on conflicts and errors with "apply to all":
  copy (F5), copy as (⇧F5), move (F6), move or rename as (⇧F6), rename in
  place (⌃F6), new folder (F7, nested paths too), move to Trash (⌘⌫),
  delete (F8), delete permanently (⇧F8), duplicate (⌘D), compress to zip
  with an optional AES-256 password (F9 / ⇧F9), symbolic and hard links.
- **Batch rename** (⌃M) with the placeholder language of Nimble Commander:
  `[N]` `[E]` `[A]` `[P]` `[G]` with substrings (`[N2-4]`, `[N-5,3]`), dates
  `[d] [Y] [M] [D] [t]…`, counters `[C5+5/2:3]`, case `[U] [L] [F] [n]`, then
  a search and replace and a case change, with a live preview.
- **File attributes** (⌃A): permissions, flags, owner, group and dates of
  one or several items, recursively if asked.
- **Archives** open as folders on Return: zip (jar, apk…), tar alone or
  with gzip, bzip2, xz or zstd, 7z, rar, ISO images (Joliet and Rock Ridge
  names), and one file compressed with gzip, bzip2, xz or zstd; ⌘↓ opens
  any file whose first bytes say it is one. Encrypted zip, 7z and rar
  archives ask for their password once. Copy out of them (F5), open
  members with their application, or Extract To (⌥F9, `:extract dir`):
  every archive selected into a folder you pick, each into a folder named
  after it when it holds more than one item, with progress, conflict
  questions and cancellation. Large archives open fast: the member list
  is read once (from the archive's directory where it has one, in one
  pass otherwise) and kept while the file is unchanged.
- **Flat view** (⌥⌘B, Vim `zf`, `:flat`): every file under the folder in
  one list, each with its folder beside its name, as Total Commander's
  branch view; sort, select, quick search and every command across the
  whole tree; the first rows show at once even in a huge tree; works
  inside archives too.
- **Finder tags** (macOS): coloured dots after the names, as Finder
  shows them, and the names in their tip; ⌃⌘T (or `:tag red,work`,
  `:tag -red`) tags the selection from a menu that checks what every item
  has and dashes what some have, with new tags of any name and colour.
- **Go anywhere**: the Go To pop-up (F1 / F2) with favorites, volumes, the
  other panel's places and the history; quick lists for parents (⌘1),
  history (⌘2), favorites (⌘3) and volumes (⌘4, with eject); Go to Folder
  (⇧⌘G); Home, Desktop, Documents, Downloads, Applications and Utilities
  on their chords; ⌘↑ up, ⌘↓ into (an archive with any extension), ⌘→ follows
  a symlink.
- **Built-in viewer** (F3, Space): text, hex and preview modes, windows
  of large files, find (⌘F), go to an offset (⌘L).
- **Find files** (⌘F): by mask or regular expression, by contents (phrase
  or words, case, not containing), by size; results stream in; go to a
  hit or view it. On macOS it can ask the Spotlight index first (much
  faster on large trees), checking every hit as a walk would.
- **Command palette** (⌘P): every command that can run where you are,
  found by a fuzzy search (English names work in any language), the ones
  used lately first, with their keys; it runs as the key would.
- **Jump to a frequent folder** (⌘G, Vim `gj` and `:z words`): the folders
  you visit, ranked by frecency as zoxide ranks them; type parts of a path,
  open in the panel, a new tab (⌘↩) or the other panel (⌥↩).
- **Shelf** (⌥⌘S to add, ⌃⌘S to show): gather files from any folders of
  either panel, then copy or move them all into one with a button; Vim's
  `yy` / `dd` / `p` work through it.
- **Rename in an editor** (⌃⇧M): the names as text, one per line, to edit
  with the whole of a text field, beside the names they replace, checked
  as you type (empty, `/`, repeated, taken, a line too many or too few);
  swaps work.
- **The desktop's own services**: Quick Look (⌘Y, as in Finder; the
  built-in preview moved to ⇧⌘Y and Space keeps it) follows the cursor and
  steps through a selection; Share (⇧⌘S, or Share… on a row) opens the
  system's picker (macOS). Drag rows between the panels, onto a folder row,
  out to Finder or Mail, and drop files from other applications onto a
  panel or a folder (macOS, Windows, Linux): one volume moves, another
  copies, ⌥ copies and ⌘ moves, and the copy runs as any other operation.
- **Integrated terminal**, as in Nimble Commander: your shell under the
  panels (⌃` shows it and gives it the keys, again for a taller one, ⌃⇧`
  hides it; Nimble Commander's ⌃⌥↑ and ⌃⌥↓ work too where no window
  manager takes them; the edge between them drags or takes the keys), the panels
  hidden over it (⌃⌥O) or the whole window (⌥⌘O). It follows the active
  panel's folder while waiting at its prompt, and a `cd` typed in it takes
  the panel along; programs (vim, top, ssh) are left alone. Copy, paste,
  clear (⌘C, ⌘V, ⌘K) as in Terminal.app; every other key is the shell's.
  `:term make` runs a command there from Vim mode.
- **Undo and redo** (⌘Z / ⇧⌘Z) for copies, moves, the trash, renames
  (batch ones too), new folders and files, archives and synchronizations:
  what was made goes to the Trash, what moved moves back, what was trashed
  comes back; anything that changed since is named before anything moves.
- **Compare folders** (⇧F2) selects in both panels what is missing or
  newer on the other side, optionally comparing contents; **Synchronize
  folders** (⌥⇧F2) compares two trees and makes them alike both ways or
  one way, with a table of actions you can change row by row.
- **Checksums** (⌃⌘H): SHA-256, SHA-1, MD5 or BLAKE3 of files and folders,
  a pasted hash looked up, a checksum file saved or checked.
- **Find duplicates** (⇧⌘F): files with the same contents, grouped by the
  space they waste, marked by hand or by rule, moved to the Trash (and
  back with ⌘Z).
- **Servers** (⌘K, Connect to Server; `:connect sftp://me@host/srv`): SFTP,
  FTP and FTPS, WebDAV over HTTP and HTTPS in the panels like any folder:
  browse, view, copy and move both ways and between servers with progress
  and cancel, rename, make folders, delete (for good: servers have no
  trash), open a copy. Saved servers in the dialog and the Go To pop-up;
  host keys checked against `~/.ssh/known_hosts` (a changed key is
  refused, never waved through), the SSH agent and key files, passwords
  in the system keychain only when you ask; plain FTP and HTTP say they
  are not encrypted. Pure Rust underneath (russh, rustls), no OpenSSL.
- **Keyboard first, no mouse needed**: every command has a shortcut you can
  rebind (Settings → Hotkeys), click hints (⌘J) label everything clickable,
  the menu key (⌃↩, ⇧F10) opens what a right click opens, a cheat sheet
  (⌘/) lists every key of where you are, and a quiet line under the panels
  names the keys for what is under the cursor or selected (Tab for the
  other panel, F5 to copy a selection…) until you hide it.
  With multiple tabs in the active panel, it also shows how to switch them
  (`gT` / `gt` in Vim mode), using your current key bindings.
  Hints appear only when the whole entry fits; the **Shortcuts** button opens
  the cheat sheet. **Commands** in a panel's top bar opens the command palette
  for that panel (a search icon in a narrow panel). Sorting shows its field
  and direction, with the full description on hover or keyboard focus.
  On macOS, the menu bar groups file operations, navigation, view settings,
  tabs, the terminal and help; its shortcuts follow your bindings.
- **Vim mode** (Settings → Panels): `j k` move; `h l` go out and in
  in a table and step a column in the names-in-columns modes, as in
  vifm's ls-like view (`gl` and `-` go in and out in any mode), counts
  (`5j`, `3G`, `2gt`), `gg` / `G`, `H M L`, `zz zt zb`, `f` / `F` / `;` /
  `,` jump by a first letter, `v` Visual selection, `x` / Space toggle,
  `yy` / `dd` / `p` copy or move between the panels through the shelf,
  `/` searches with `n` / `N`, marks `m` / `'` kept across runs, `cw` /
  `A` / `I` rename, `:` commands (`:cd ~/src`, `:mkdir`, `:sort size!`,
  `:set hidden`, `:tabnew`, `:marks`, `:42`…) with history and Tab
  completion; the footer names the mode and shows the keys that wait.
- **Native look**: macOS HIG (with macOS 26's own metrics), Windows 11
  Fluent or GNOME HIG, chosen by the platform, light and dark. Interface in
  English and Russian.
- **Platforms**: macOS, Windows and Linux desktops. Day-to-day builds and
  runs are on macOS; the Windows and Linux looks are covered by widget tests
  and CI.
- **UI:** Flutter. **Core:** Rust (listings with full metadata, folder
  watching, operations with cancellation, archives, batch rename, find,
  the terminal's pseudo-terminal, SFTP, FTP and WebDAV), connected
  through `flutter_rust_bridge`.

## Toolchain

| Tool | Version | Notes |
|------|---------|-------|
| Flutter | pinned in `.fvmrc`, used through `fvm` | `fvm install` once |
| Rust | stable ≥ 1.85 via **rustup** | cargokit builds with `rustup run stable`, so the rustup toolchain must be current (`rustup update stable`) |
| `flutter_rust_bridge_codegen` | 2.13.0 | `cargo install flutter_rust_bridge_codegen@2.13.0` |

First-time setup:

```sh
fvm install
make get
```

## Commands

| Task | Command |
|------|---------|
| Install deps for root + every package | `make get` |
| Run the app on this machine | `make run` |
| Full quality gate (format, analyze, tests) | `make verify` |
| Rebuild the app icons from `brand/` | `make icons` |
| Rust tests only | `make test-rust` |
| Dart tests only | `make test-dart` |
| Regenerate bridge bindings after editing `rust/crates/ferryx_api/src/api` | `make codegen` |
| Regenerate localizations after editing ARB files | `make l10n` |
| Release builds (each on its own OS) | `make build-macos`, `make build-linux`, `make build-windows` |
| macOS disk image (`build/Ferryx-<version>.dmg`) | `make dmg` |
| Publish it as the GitHub release `v<version>` | `make release` |

See the [app icon guide](brand/README.md) for the SVG masters, palette,
small-size variants and generated platform resources.

## Releases

`make dmg` builds the app for Apple silicon and Intel and packs it into a
disk image with a link to Applications. `make release` publishes that
image on GitHub through `gh`, as the release `v<version>` (the version in
`pubspec.yaml`) at the commit checked out.

The app is signed ad hoc, not with a Developer ID, so a Mac that
downloaded it asks first: System Settings → Privacy & Security → Open
Anyway (or `xattr -dr com.apple.quarantine /Applications/Ferryx.app`).

## Layout

```
lib/app/                 composition root: bootstrap, dependencies, routing
packages/                Dart packages (see ARCHITECTURE.md)
packages/features/*      one package per screen or flow
rust/crates/ferryx_core  sorting, natural collation, masks, quick search, batch rename
rust/crates/ferryx_vfs   listings, metadata, watching, volumes, attributes, links, archives, servers
rust/crates/ferryx_ops   copy, move, delete, trash, duplicate, compress, extract, sizes, find, transfers
rust/crates/ferryx_term  the terminal's shell in a pseudo-terminal: batched output, its state
rust/crates/ferryx_api   flutter_rust_bridge surface and the event stream
rust/crates/ferryx_test_servers  in-process SFTP, FTP and WebDAV servers for the tests
rust_builder/            cargokit FFI plugin that compiles the Rust crate
brand/                   app icon masters, one per desktop (make icons)
linux/packaging/         desktop entry and hicolor icons for Linux packages
```

Ferryx keeps its preferences in the platform's preference store (one JSON
value under `ferryx.preferences`): theme and language, the panels' tabs
and their places, view modes, favorites, editors, tools and shortcut
overrides. Beside it, under keys of their own, it keeps the folders you
visit with their frecency (`ferryx.folderFrecency`, for Jump to Folder)
and the commands you ran from the palette (`ferryx.recentCommands`) and
the server addresses you connected to (`ferryx.recentServers`, never with
a password). Saved servers are in the preferences without passwords; a
password or key passphrase goes to the system keychain only when you tick
Remember, and a host key you trust is remembered in Ferryx's own
`known_hosts` (`~/Library/Application Support/Ferryx/` on macOS), never in
yours. A file opened from a server is copied to the system's temporary
folder. Nothing else is written outside the folders you work in.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the rules that keep the codebase
navigable and [CLAUDE.md](CLAUDE.md) for the working conventions.
