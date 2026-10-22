#!/usr/bin/env bash
# Publishes the macOS disk image on the repository's Releases page through
# `gh`, as the release v<version> (the version in pubspec.yaml) at the
# commit checked out. `make release` runs `check` before it builds the
# image (`make dmg`) and `publish` after.
#
#   check    the tree is clean, the commit is on GitHub and the version is
#            not released from another commit yet: the image is built from
#            what GitHub holds, and a version names one build
#   publish  creates the release with the image, or replaces the image of
#            this commit's release; prints the release's page
set -euo pipefail
cd "$(dirname "$0")/../.."

version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
tag=v$version
commit=$(git rev-parse HEAD)
image=build/Ferryx-$version.dmg

fail() {
  echo "release: $*" >&2
  exit 1
}

# The commit the tag names on GitHub, empty when there is no such tag.
released_from() {
  git ls-remote --tags origin "refs/tags/$tag^{}" "refs/tags/$tag" |
    sort -k2 -r | head -n 1 | cut -f1
}

check() {
  gh auth status > /dev/null 2>&1 || fail "gh is not signed in: gh auth login"
  [ -z "$(git status --porcelain)" ] ||
    fail "uncommitted changes: commit and push them first"
  git fetch --quiet origin
  [ -n "$(git branch -r --contains "$commit")" ] ||
    fail "$(git rev-parse --short HEAD) is not on GitHub: push it first"
  local from
  from=$(released_from)
  if [ -n "$from" ] && [ "$from" != "$commit" ]; then
    fail "$tag is released from $(git rev-parse --short "$from"):" \
      "raise the version in pubspec.yaml"
  fi
}

publish() {
  [ -f "$image" ] || fail "no $image: make dmg"
  [ "$(git rev-parse HEAD)" = "$commit" ] || fail "the commit changed"
  if gh release view "$tag" > /dev/null 2>&1; then
    gh release upload "$tag" "$image" --clobber
  else
    gh release create "$tag" "$image" --target "$commit" \
      --title "Ferryx $version" --generate-notes
  fi
  gh release view "$tag" --json url --jq .url
}

case "${1:-}" in
  check) check ;;
  publish) publish ;;
  *) fail "usage: $0 check|publish" ;;
esac
