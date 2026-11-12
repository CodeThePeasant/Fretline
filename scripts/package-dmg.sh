#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -d dist/Fretline.app ]; then
  echo '请先运行 scripts/build-app.sh' >&2
  exit 1
fi
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/fretline-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto dist/Fretline.app "$STAGING/Fretline.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Fretline -srcfolder "$STAGING" -ov -format UDZO "dist/Fretline-0.1.0-$(uname -m).dmg"
