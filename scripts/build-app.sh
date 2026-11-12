#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/dist/Fretline.app"
swift build -c release
python3 scripts/make_demo.py
(
  cd engine
  uv run --frozen pyinstaller --noconfirm --clean --onedir --name guitartab-engine \
    --collect-all librosa --collect-all imageio_ffmpeg --collect-all lazy_loader \
    --collect-all soxr --hidden-import scipy.special._special_ufuncs cli.py
)
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/GuitarTab "$APP/Contents/MacOS/GuitarTab"
ditto engine/dist/guitartab-engine "$APP/Contents/Resources/engine"
cp examples/demo-solo.wav "$APP/Contents/Resources/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
if [ -f assets/Fretline.icns ]; then cp assets/Fretline.icns "$APP/Contents/Resources/"; fi
codesign --force --deep --sign - "$APP"
echo "已生成：$APP"
