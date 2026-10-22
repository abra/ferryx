#!/usr/bin/env bash
# Packs the release build of the macOS app into a disk image that holds
# the app and a link to /Applications to drag it onto. Run after
# `flutter build macos --release` (`make dmg` does both); prints the
# image's path, build/Ferryx-<version>.dmg, the version from pubspec.yaml.
set -euo pipefail
cd "$(dirname "$0")/../.."

version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
app=build/macos/Build/Products/Release/Ferryx.app
stage=build/dmg
image=build/Ferryx-$version.dmg

if [ ! -d "$app" ]; then
  echo "no $app: run flutter build macos --release first" >&2
  exit 1
fi
# A signature broken by a copy or a late edit would make macOS refuse the
# app on the other machine, not here.
codesign --verify --deep --strict "$app"

rm -rf "${stage:?}" "${image:?}"
mkdir -p "$stage"
ditto "$app" "$stage/Ferryx.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Ferryx $version" -srcfolder "$stage" \
  -format UDZO -ov "$image"
rm -rf "${stage:?}"
echo "$image"
