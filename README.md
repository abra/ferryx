<p align="center"><img src="brand/ferryx-256.png" width="128" height="128" alt="Ferryx"></p>

# Ferryx

A dual-pane file manager for the desktop, built for the keyboard: the
orthodox two-panel workflow of the classic commanders with the look and
manners of each desktop. The interface is Flutter; everything that touches
files is Rust.

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
  or case-sensitive comparison; the indicator in the panel's corner names
  the order (`n`, `S`, `m`…).
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
- **Archives** open as folders on Return: zip, jar, tar, tar.gz; copy out of
  them (F5) or open members with their application.
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
  hit or view it.
- **The desktop's own services**: Quick Look (⌘Y, as in Finder; the
  built-in preview moved to ⇧⌘Y and Space keeps it) follows the cursor and
  steps through a selection; Share (⇧⌘S, or Share… on a row) opens the
  system's picker (macOS). Drag rows between the panels, onto a folder row,
  out to Finder or Mail, and drop files from other applications onto a
  panel or a folder (macOS, Windows, Linux): one volume moves, another
  copies, ⌥ copies and ⌘ moves, and the copy runs as any other operation.
- **Keyboard first, no mouse needed**: every command has a shortcut you can
  rebind (Settings → Hotkeys), click hints (⌘J) label everything clickable,
  the menu key (⌃↩, ⇧F10) opens what a right click opens, a cheat sheet
  (⌘/) lists every key of where you are, and a quiet line under the panels
  names the keys for what is under the cursor or selected (Tab for the
  other panel, F5 to copy a selection…) until you hide it.
- **Vim mode** (Settings → Panels): `h j k l` move and enter, counts
  (`5j`, `3G`, `2gt`), `gg` / `G`, `H M L`, `zz zt zb`, `f` / `F` / `;` /
  `,` jump by a first letter, `v` Visual selection, `x` / Space toggle,
  `yy` / `dd` / `p` copy or move between the panels through a register,
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
  watching, operations with cancellation, archives, batch rename, find),
  connected through `flutter_rust_bridge`.

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
rust/crates/ferryx_vfs   listings, metadata, watching, volumes, attributes, links, archives
rust/crates/ferryx_ops   copy, move, delete, trash, duplicate, compress, extract, sizes, find
rust/crates/ferryx_api   flutter_rust_bridge surface and the event stream
rust_builder/            cargokit FFI plugin that compiles the Rust crate
brand/                   app icon masters, one per desktop (make icons)
linux/packaging/         desktop entry and hicolor icons for Linux packages
```

Ferryx keeps its preferences in the platform's preference store (one JSON
value under `ferryx.preferences`): theme and language, the panels' tabs
and their places, view modes, favorites, editors, tools and shortcut
overrides. Nothing else is written outside the folders you work in.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the rules that keep the codebase
navigable and [CLAUDE.md](CLAUDE.md) for the working conventions.
