#!/bin/sh
# Inside the Linux container: copies the working tree mounted at /src into
# /work (a volume that keeps the builds between runs), leaving out what
# each system builds for itself, then runs the make targets given.
set -eu
rsync -a --delete \
  --exclude .git/ --exclude .dart_tool/ --exclude build/ --exclude .fvm/ \
  --exclude rust/target/ --exclude Pods/ --exclude test/ui/snapshots/ \
  /src/ /work/
cd /work
make get FLUTTER=flutter DART=dart
make "$@" FLUTTER=flutter DART=dart
