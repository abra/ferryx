# Linux packaging

These are resources for a Linux package; the repository does not currently
produce a deb, rpm, Flatpak or AUR package. A packager installs the desktop
entry and icons so desktops show Ferryx's name and icon:

| File | Installed to |
|------|--------------|
| [`dev.ferryx.ferryx.desktop`](dev.ferryx.ferryx.desktop) | `share/applications/` |
| `icons/hicolor/*` | `share/icons/hicolor/` (keep the folder layout) |
| `icons/hicolor/256x256/apps/dev.ferryx.ferryx.png` | `data/app_icon.png` beside the packaged executable, for the X11 window icon |

The entry is named after the application id (`APPLICATION_ID` in
`../CMakeLists.txt`): GNOME on Wayland matches a window to its entry by that
id, and takes the icon from the theme. `Exec` assumes the `ferryx` binary on
`PATH`; a package points it at its install location. On X11 the window's
class is the application id too (the runner calls `g_set_prgname`), so
`StartupWMClass` is `dev.ferryx.ferryx`. The window icon the runner sets for
X11 is loaded from the bundle's `data/app_icon.png`. The current CMake
install rules do not copy that file; the packaging step must copy the
256 px hicolor PNG there explicitly. `make build-linux` creates the Flutter
bundle but does not install the desktop entry or icon theme into the system.

For a local bundle, run from the repository root after `make build-linux`
(replace `x64` with the architecture of your build):

```sh
cp linux/packaging/icons/hicolor/256x256/apps/dev.ferryx.ferryx.png \
  build/linux/x64/release/bundle/data/app_icon.png
```

Not here yet: AppStream metainfo (`dev.ferryx.ferryx.metainfo.xml` in
`share/metainfo/`), which Flatpak and software centres need.

The icons are generated: edit the [masters in `../../brand`](../../brand/README.md)
and run `make icons`. Sizes up to 32 px use the dedicated small drawing; the
scalable and symbolic SVGs are copied from their respective masters.
