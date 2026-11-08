<p align="center"><img src="brand/ferryx-256.png" width="128" height="128" alt="Ferryx"></p>

# Ferryx

A dual-pane file manager for the desktop, built for the keyboard: the
orthodox two-panel workflow of the classic commanders with a compact blue
interface and each desktop's conventions. The interface is Flutter; file
listings, operations and the filesystem core are Rust.

![Ferryx on macOS in the Balanced light theme, with pocketbook and afrog/v1 directories, folder tabs and contextual keyboard hints](docs/screenshots/ferryx-macos.png)

## Features

Shortcuts below are the **macOS defaults**: ⌘ Command, ⌥ Option,
⌃ Control, ⇧ Shift. Windows and Linux have their own defaults; see
Settings → Hotkeys or the **Shortcuts** button for your current bindings.
Vim mode is optional and off by default.

- **Two panels** with tabs (⌘T), each with its own history (⌘[ / ⌘]),
  sorting and view mode. Tab switches panels; ⌃Tab / ⌃⇧Tab switch to the
  next / previous tab within a panel (also ⇧⌘] / ⇧⌘[; Vim `gt` / `gT`).
  Swap (⌘U) or show the active folder in the other panel (⌥⌘U), or collapse
  to one panel (⇧⌘P). By default the panels sit beside each other in a wide
  window and stack in a tall one; ⌥⌘P changes the arrangement. The edge
  between them moves by drag or by the keys (⌥⌘\).
- **Cursor and selection kept apart**, as orthodox managers have them:
  the arrows move the cursor, ⇧ with them selects, Insert / ⌥Space toggles
  a row, ⌘A / ⌥⌘A / ⌃⌘A select all, none, or invert, ⌘= selects by a mask
  or a regular expression.
- **Quick search**: type a few letters and the matching names are
  underlined (fuzzy, anywhere, at the beginning or the end; optionally only
  the matches show). Esc clears. With Vim mode enabled, `/` starts the search.
- **View modes**: Brief (names in columns) and List (a table of columns);
  five presets on ⌃1–⌃5, editable in Settings.
- **Sorting** by name, extension, modified time, size, created time, added
  time and accessed time (⌃⌘1–⌃⌘7, respectively), folders first or not,
  natural, case-insensitive or case-sensitive comparison; the panel header
  shows the sort field and direction, with a compact icon and full tooltip
  in narrow panels.
- **Operations in the background** with progress, speed and time left,
  pause and stop, and questions on conflicts and errors with "apply to all":
  copy (F5), copy as (⇧F5), move (F6), move or rename as (⇧F6), rename in
  place (⌃F6), new folder (F7, nested paths too), move to Trash (⌘⌫),
  delete dialog (F8, Trash selected by default), permanent-delete dialog
  (⇧F8), duplicate (⌘D), compress to zip with an optional AES-256 password
  (F9 / ⇧F9), symbolic and hard links.
- **Batch rename** (⌃M) for local files, with Nimble Commander-style placeholders:
  `[N]` `[E]` `[A]` `[P]` `[G]` with substrings (`[N2-4]`, `[N-5,3]`), dates
  `[d] [Y] [M] [D] [t]…`, counters `[C5+5/2:3]`, case `[U] [L] [F] [n]`, then
  a search and replace and a case change, with a live preview.
- **File attributes** (⌃A) for local files: permissions and modified/accessed
  times of one or several items, recursively if asked. Unix supports owner
  and group changes; file flags are macOS-only, and Windows permissions
  editing controls the read-only flag.
- **Archives** open as read-only folders on Return: zip (jar, apk…), tar alone or
  with gzip, bzip2, xz or zstd, 7z, rar, ISO images (Joliet and Rock Ridge
  names), and one file compressed with gzip, bzip2, xz or zstd; ⌘↓ opens
  any file whose first bytes say it is one. Encrypted zip, 7z and rar
  archives remember their password for the current app session. Copy out
  of them (F5), open members with their application, or Extract To
  (⌥F9, `:extract dir`):
  every archive selected into a folder you pick, each into a folder named
  after it by default when it has multiple top-level items, with progress,
  conflict questions and cancellation. Recent archive indexes are cached
  while the files remain unchanged; the first read may require a full pass.
  Editing an extracted copy does not update the archive. Multi-volume RAR
  browsing lists only the first volume's members.
- **Flat view** (⌥⌘B, Vim `zf`, `:flat`): every file under the folder in
  one list, each with its folder beside its name, as Total Commander's
  branch view; sort, select and quick search across the whole tree, with
  rows streamed as they are found. Works in local folders and archives;
  archive contents remain read-only.
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
- **Built-in viewer** (F3, Space): text, hex and image preview modes,
  windowed reads of large text/binary files, find (⌘F), go to an offset (⌘L).
  Image previews read the whole file and are limited to 64 MiB.
- **Find files** (⌘F): by mask or regular expression, by contents (phrase
  or words, case, not containing), by size; results stream in; go to a
  hit or view it. Searches local folders; on macOS it can use the Spotlight
  index, checking each returned hit against the search criteria.
- **Command palette** (⌘P): commands for the current panel, viewer or dialog,
  found by a fuzzy search (English names work in any language), the ones
  used lately first, with their keys; it runs as the key would.
- **Jump to a frequent folder** (⌘G, Vim `gj` and `:z words`): the folders
  you visit, ranked by how often and how recently you visit; type parts of a path,
  open in the panel, a new tab (⌘↩) or the other panel (⌥↩).
- **Shelf** (⌥⌘S to add, ⌃⌘S to show): gather files from local folders of
  either panel, then copy or move them all into one with a button; Vim's
  `yy` / `dd` / `p` work through it.
- **Rename in an editor** (⌃⇧M): local file names in a built-in text dialog,
  one per line, beside the names they replace, checked
  as you type (empty, `/`, repeated, taken, a line too many or too few);
  swaps work.
- **The desktop's own services**: on macOS, Quick Look (⌘Y, as in Finder;
  built-in preview uses ⇧⌘Y or Space) follows the cursor and
  steps through a selection; Share (⇧⌘S, or Share… on a row) opens the
  system's picker. Drag local files between the panels, onto a folder row,
  or between Ferryx and other applications (macOS, Windows, Linux): a drop
  on the same volume moves, another volume copies. The transfer runs as
  any other operation. On macOS, ⌥ forces
  copy and ⌘ forces move. Windows drag modifiers are not reported by the
  drag-and-drop plugin, so the volume rule determines the operation.
- **Integrated terminal**, as in Nimble Commander: your shell under the
  panels (⌃\` shows it and gives it the keys, again for a taller one, ⌃⇧\`
  hides it; Nimble Commander's ⌃⌥↑ and ⌃⌥↓ work too where no window
  manager takes them; the edge between them drags or takes the keys), the panels
  hidden over it (⌃⌥O) or the whole window (⌥⌘O). On macOS and Linux, it follows
  the active local folder while waiting at its prompt, and a `cd` typed in it
  takes the panel along; programs (vim, top, ssh) are left alone. Windows
  does not synchronize the shell and panel folders. Copy, paste and clear
  (⌘C, ⌘V, ⌘K) work as in Terminal.app; shell control keys reach the shell,
  while terminal controls and supported window shortcuts remain available.
  There is one terminal session per window.
  `:term make` runs a command there from Vim mode.
- **Undo and redo** (⌘Z / ⇧⌘Z) for supported local changes: copies, moves,
  the trash, renames (batch ones too), new folders and files, archive
  creation/extraction and synchronizations:
  what was made goes to the Trash, what moved moves back, what was trashed
  comes back. A preflight check reports missing items, changed file metadata
  and conflicting paths. The last 100 steps are kept in memory for this
  session only; overwritten contents, permanent deletions and operations
  involving servers cannot be undone.
- **Compare folders** (⇧F2) compares the current listings, without descending
  into subfolders, and selects what is missing or newer on the other side;
  optional content comparison requires two local folders. **Synchronize
  folders** (⌥⇧F2) compares two local trees recursively and makes them alike
  both ways or one way, with a table of actions you can change row by row.
- **Checksums** (⌃⌘H): SHA-256, SHA-1, MD5 or BLAKE3 of local files and folders,
  a pasted hash looked up, a checksum file saved or checked.
- **Find duplicates** (⇧⌘F): local files with the same contents, grouped by the
  space they waste, marked by hand or by rule, moved to the Trash (and
  back with ⌘Z).
- **Servers** (⌘K, Connect to Server; `:connect sftp://me@host/srv`): SFTP,
  FTP and FTPS, WebDAV over HTTP and HTTPS in the panels like any folder:
  browse, view, copy and move both ways and between servers with progress
  and cancel, rename, make folders, delete (for good: servers have no
  trash), open a copy in an external application. Changes to that copy are
  not uploaded automatically. Saved servers in the dialog and the Go To pop-up;
  host keys checked against `~/.ssh/known_hosts` (a changed key is
  refused, never waved through), the SSH agent and key files, passwords
  in the system keychain only when you ask; plain FTP and HTTP say they
  are not encrypted. Uses russh and rustls, without an OpenSSL dependency.
  Server folders refresh on demand (⌘R), with no background change watching.
- **Keyboard controls**: assign or rebind shortcuts in Settings → Hotkeys;
  some commands have no default binding. Click hints (⌘J) label clickable controls,
  the menu key (⌃↩, ⇧F10) opens what a right click opens, a cheat sheet
  (⌘/) lists the current bindings by section with search. A quiet line under
  the panels names the keys for what is under the cursor or selected (Tab for the
  other panel, F5 to copy a selection…) until you hide it.
  With multiple tabs in the active panel, it also shows how to switch them
  (`gT` / `gt` in Vim mode), using your current key bindings.
  Hints appear only when the whole entry fits; the **Shortcuts** button opens
  the cheat sheet. **Commands** in a panel's top bar opens the command palette
  for that panel (a search icon in a narrow panel). Sorting shows its field
  and direction, with the full description on hover or keyboard focus.
  On macOS, the menu bar groups file operations, navigation, view settings,
  tabs, the terminal and help; its shortcuts follow your bindings.
- **Vim mode** (Settings → Panels → Vim keys): `j k` move; `h l` go out and in
  in a table and step a column in the names-in-columns modes, as in
  vifm's ls-like view (`gl` and `-` go in and out in any mode), counts
  (`5j`, `3G`, `2gt`), `gg` / `G`, `H M L`, `zz zt zb`, `f` / `F` / `;` /
  `,` jump by a first letter, `v` Visual selection, `x` / Space toggle,
  `yy` / `dd` / `p` copy or move between the panels through the shelf,
  `/` searches with `n` / `N`, marks `m` / `'` kept across runs, `cw` /
  `A` / `I` rename, `:` commands (`:cd ~/src`, `:mkdir`, `:sort size!`,
  `:set hidden`, `:tabnew`, `:marks`, `:42`…) with history and Tab
  completion; the footer names the mode and shows the keys that wait.
- **Appearance**: Balanced light and dark themes with blue accents, soft
  selection and monospace file metadata. Compact controls and system fonts
  follow macOS HIG (including macOS 26's metrics), Windows 11 Fluent or
  GNOME HIG. Interface in English and Russian. See the
  [design prototypes](docs/prototypes/protocol-style/README.md).
- **Platforms**: macOS, Windows and Linux desktops. Day-to-day builds and
  runs are on macOS; CI is configured to run checks, release builds and
  launch smoke checks on Windows and Linux. See [CI](#ci) below.
- **UI:** Flutter. **Core:** Rust (listings with full metadata, folder
  watching, operations with cancellation, archives, batch rename, find,
  the terminal's pseudo-terminal, SFTP, FTP and WebDAV), connected
  through `flutter_rust_bridge`.

## Toolchain

| Tool | Version | Notes |
|------|---------|-------|
| Flutter | 3.47.7, pinned in [`.fvmrc`](.fvmrc) | Use `fvm flutter` / `fvm dart`; the pinned Flutter includes Dart |
| Rust | current stable via **rustup** | cargokit uses `rustup run stable`; keep it current with `rustup update stable` |
| `flutter_rust_bridge_codegen` | 2.13.0 | Only needed when regenerating bindings: `cargo install flutter_rust_bridge_codegen@2.13.0 --locked` |

The workspace still declares `rust-version = "1.85"`, but the locked RAR
dependencies require at least Rust **1.97.1**. Rust 1.85 is insufficient
for the current lockfile; CI uses stable rather than testing that old minimum.

Install FVM, rustup and the native tools for the desktop you build on:

- **macOS:** Xcode with its command-line tools and licenses configured, plus
  CocoaPods for this project's plugins. See [Flutter's macOS setup](https://docs.flutter.dev/platform-integration/macos/setup).
- **Windows:** Visual Studio with **Desktop development with C++**, as in
  [Flutter's Windows setup](https://docs.flutter.dev/platform-integration/windows/setup).
  The Makefile also needs GNU Make and a Bash-compatible shell (CI uses Git Bash).
- **Linux:** Clang, CMake, Ninja, pkg-config, GTK 3 and C++ development libraries;
  CI also installs `liblzma-dev`. See [Flutter's Linux setup](https://docs.flutter.dev/platform-integration/linux/setup)
  and the [Linux container dependencies](tools/linux/Dockerfile).

First-time setup, from the repository root:

```sh
fvm install
rustup update stable
rustup override set stable
rustup component add rustfmt clippy --toolchain stable
fvm flutter doctor -v
make get
```

The Makefile calls `cargo` from PATH, while cargokit uses rustup's stable
toolchain. Ensure they select the same Rust installation. Generated bridge
bindings are checked in; normal builds do not require running codegen.

## Commands

| Task | Command |
|------|---------|
| Install deps for root + every package | `make get` |
| Run on macOS / Linux | `make run` |
| Run on Windows | `fvm flutter run -d windows` |
| Full quality gate (format, analyze, tests) | `make verify` |
| Rebuild the app icons from `brand/` | `make icons` |
| Rust tests only | `make test-rust` |
| Dart tests only | `make test-dart` |
| Native AppKit window tests (macOS + Xcode, additional to `verify`) | `make test-macos` |
| Build the Rust library used by integration tests | `make core` (also run by `make test-dart`) |
| Regenerate bridge bindings after editing `rust/crates/ferryx_api/src/api` | `make codegen` |
| Regenerate localizations after editing ARB files | `make l10n` |
| Release builds (each on its own OS) | `make build-macos`, `make build-linux`, `make build-windows` |
| macOS disk image (`build/Ferryx-<version>.dmg`) | `make dmg` |
| Publish it as the GitHub release `v<version>` | `make release` |
| Linux quality gate in Docker | `make linux` (or `make linux LINUX="test-dart build-linux"`) |
| List all targets | `make help` |

`make codegen` needs the pinned Flutter/Dart SDK on PATH because the
generator invokes them directly; `fvm exec make codegen` supplies that
environment. After changing Rust or regenerating the bridge, stop and
restart `flutter run` completely: hot reload/restart keeps the old native
library loaded.

See the [app icon guide](brand/README.md) for the SVG masters, palette,
small-size variants and generated platform resources. `make icons` needs
Python 3 and `rsvg-convert` (librsvg).
See [Linux packaging](linux/packaging/README.md) for desktop-entry and icon
installation; `make build-linux` produces an app bundle, not an installer.

## CI

The [GitHub Actions workflow](.github/workflows/ci.yml) runs `make verify`,
a release build and a short launch check on Linux and Windows, retaining
screenshots as artifacts. It runs on pull requests, pushes to `ci/**`
branches and manual dispatch; ordinary pushes to other branches do not
trigger it. There is no macOS CI job.

## Releases

On macOS, `make dmg` builds the release app and packs it into
`build/Ferryx-<version>.dmg` with a link to Applications. `make release`
publishes that image through an authenticated `gh` as `v<version>` from
`pubspec.yaml`, excluding the `+build` suffix.

Publishing requires a clean working tree and a commit already pushed to
the remote. If that version's tag points to a different commit, the script
requires a version bump. Repeating the release at the same commit replaces
its DMG asset. Windows and Linux have build targets, but this publishing
script packages and uploads only macOS.

The macOS app is signed ad hoc and is not notarized. For a downloaded build
you trust, follow Apple's [Open Anyway instructions](https://support.apple.com/en-us/102445)
in System Settings → Privacy & Security after attempting to open it.

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
docs/screenshots/        UI images used in this README
linux/packaging/         desktop entry and hicolor icons for Linux packages
tools/                   Linux container and macOS packaging/release scripts
```

## Settings and stored data

Ferryx keeps its preferences in the platform's preference store (one JSON
value under `ferryx.preferences`): theme and language, the panels' tabs
and their places, view modes, favorites, editors, tools and shortcut
overrides. Beside it, under keys of their own, it keeps the folders you
visit with their frecency (`ferryx.folderFrecency`, for Jump to Folder)
and the commands you ran from the palette (`ferryx.recentCommands`) and
the server addresses you connected to (`ferryx.recentServers`, never with
a password). Saved servers are in the preferences without passwords; a
password or key passphrase goes to the system keychain only when you tick
Remember.

Accepted SSH host keys go to Ferryx's own `known_hosts`; the user's and
system's OpenSSH files are read without being modified:

| Platform | Ferryx host-key file |
|----------|---------------------|
| macOS | `~/Library/Application Support/Ferryx/known_hosts` |
| Windows | `%APPDATA%/Ferryx/known_hosts` (fallback: `~/AppData/Roaming/Ferryx/known_hosts`) |
| Linux | `$XDG_CONFIG_HOME/ferryx/known_hosts` (fallback: `~/.config/ferryx/known_hosts`) |

Files opened externally from servers or archives are copied under `Ferryx/`
in the system temporary directory; large compressed archive members may
also be unpacked there for the viewer. These copies do not synchronize
changes back to their source. Undo history and archive passwords stay in
memory and are lost when the app exits.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the rules that keep the codebase
navigable and [CLAUDE.md](CLAUDE.md) for the working conventions.
