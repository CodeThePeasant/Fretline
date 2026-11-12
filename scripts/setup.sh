#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v uv >/dev/null; then
  echo '请先安装 uv：https://docs.astral.sh/uv/getting-started/installation/' >&2
  exit 1
fi
uv sync --project engine --python 3.11 --frozen
python3 scripts/make_demo.py
swift build
echo '就绪。运行 swift run GuitarTab，或 scripts/build-app.sh 打包。'
