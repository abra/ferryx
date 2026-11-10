# Ferryx: Protocol Explorer style study

Open [index.html](index.html) in a desktop browser. No server, package
installation or internet access is needed. Fonts are loaded from Ferryx's
existing `component_library` assets.

Reference: [Protocol Explorer](https://protocol-explorer-alpha.vercel.app/).
The prototypes adapt its blue ink, fine borders, restrained surfaces and
technical typography to Ferryx's existing two-panel layout. The source,
icons and layout here are independently implemented; the reference's
application code and assets are not bundled.

## Variants

| Variant | Direction | Preview |
|---------|-----------|---------|
| A · Чертёж | Closest to the reference: blue monochrome typography, fine outlines, nearly square controls | [PNG](blueprint.png) |
| B · Баланс | Recommended for daily use: system text for file names, monospace metadata, quieter blue borders | [PNG](balanced.png) |
| C · Ночной | Dark interpretation: navy surfaces, readable blue-gray metadata and soft blue focus | [PNG](night.png) |

The [command palette preview](balanced-commands.png) shows the same visual
language applied to an overlay in variant B.

All three use the same layout and density: 13 px file names, 22 px file
rows, 52 px pane toolbar, 28 px tabs and 22 px column headers. There are no
large dashboard cards or enlarged controls. Screenshots show the window at
1280 × 800 with a device scale factor of 1; browser zoom should remain 100%.

## Interaction

- Switch themes with A/B/C; file state stays intact.
- Click tabs, add or close one, or use `gt` / `gT` while a file list has focus.
- Move the cursor with arrows or `j` / `k`; Space marks files independently.
- Tab changes panels; Shift+Tab leaves the file list for normal browser focus.
- Enter or a double-click opens a folder; F3 opens the sample viewer.
- The Commands button or Cmd/Ctrl+P opens a searchable command palette.
- F5 opens a copy dialog and simulates progress, adding entries to the other
  panel's fixture. No real files are read, modified or copied.
- Click the terminal control to inspect its appearance. It is a static
  shell preview, not an executable terminal.

The browser reserves some desktop shortcuts, including Cmd+T and Ctrl+Tab.
Use the plus button and `gt` / `gT` in this prototype. Reloading restores
the fixture data. Buttons and native dialogs support keyboard focus; hints
are hidden as whole entries when the window is narrow.

For an unobstructed window view, append `?variant=blueprint&capture=1`,
`?variant=balanced&capture=1` or `?variant=night&capture=1` to the HTML URL.

## Flutter implementation

The Flutter app now implements variant B's direction in both light and
dark appearances. These browser prototypes remain independent fixtures
for comparing the original concepts, not the production UI.

Actual Flutter widget previews:
[light](../../screenshots/ferryx-balanced-light.png) and
[dark](../../screenshots/ferryx-balanced-dark.png). They use sample file
data at 1280 × 800 with macOS metrics and fonts; native window buttons are
outside the rendered widget tree.

The implementation uses the existing component architecture:

- `AppPalette` supplies two constant palettes through `AppColorsExt`.
  Soft selections use `onSelection` / `onSelectionMuted`; filled buttons
  keep the separate `accent` / `onAccent` pair.
- `AppMetrics` retains each platform's density and native window controls.
  `AppTypography` keeps system file names and monospace metadata, including
  accessibility text scaling and matching column measurements.
- `AppTabStrip` uses normal platform colors for the selected tab, without
  an accent underline; the active area has an `AppFocusArea` outline.
  File cursors have a leading accent; marked files retain their independent
  check marks. Both become neutral in an inactive panel or window.
- Headers, hints, menus and dialogs share the same surface roles. Existing
  `ShortcutMap` bindings and command handlers provide the real behavior.
- Contrast and component tests cover selection text, controls, native
  geometry and keyboard focus in both themes.

No Rust or filesystem architecture changes are required for the visual
direction. Production file lists keep their existing virtualization;
the small DOM fixtures here are only for comparing appearance and interaction.
