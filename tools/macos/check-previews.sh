#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

fixtures=$(mktemp -d "${TMPDIR:-/tmp}/ferryx-preview.XXXXXX")
trap 'rm -rf "$fixtures"' EXIT
(
  cd packages/pagecraft/test/fixtures/epub/epub2
  zip -qr "$fixtures/book.epub" META-INF OPS
)

binary=${1:-build/macos/Build/Products/Release/Ferryx.app/Contents/MacOS/Ferryx}
python3 - "$binary" "$fixtures/book.epub" <<'PY'
import subprocess
import sys
from pathlib import Path

paths = [
    sys.argv[1],
    sys.argv[2],
    "packages/pagecraft/test/fixtures/pdf/figure.pdf",
    "rust/crates/ferryx_core/tests/fixtures/office.zip",
]
subprocess.run([Path(path).resolve() for path in paths], timeout=120, check=True)
PY
