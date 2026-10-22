# Linux packaging

What a package (deb, rpm, Flatpak, AUR) installs so desktops show Ferryx's
name and icon:

| File | Installed to |
|------|--------------|
| `dev.ferryx.ferryx.desktop` | `share/applications/` |
| `icons/hicolor/*` | `share/icons/hicolor/` (keep the folder layout) |

The entry is named after the application id (`APPLICATION_ID` in
`../CMakeLists.txt`): GNOME on Wayland matches a window to its entry by that
id, and takes the icon from the theme. `Exec` assumes the `ferryx` binary on
`PATH`; a package points it at its install location. On X11 the window's
class is the application id too (the runner calls `g_set_prgname`), so
`StartupWMClass` is `dev.ferryx.ferryx`. The window icon the runner sets for
X11 is the bundle's `data/app_icon.png`, the 256 px hicolor PNG that
`../CMakeLists.txt` copies there.

Not here yet: AppStream metainfo (`dev.ferryx.ferryx.metainfo.xml` in
`share/metainfo/`), which Flatpak and software centres need.

The icons are generated: edit the masters in `../../brand` and run
`make icons`.
