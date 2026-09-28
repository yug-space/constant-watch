#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing.sh
uv sync --locked --python 3.12 --group packaging --extra dev
CW_RUNTIME_BUILD="$HOME/Library/Caches/Constant Watch/packaging"
mkdir -p "$CW_RUNTIME_BUILD"
.venv/bin/python -m PyInstaller --noconfirm --distpath "$CW_RUNTIME_BUILD/frozen" --workpath "$CW_RUNTIME_BUILD/pyinstaller" scripts/runtime.spec
xattr -cr "$CW_RUNTIME_BUILD/frozen/Runtime.app"
codesign --force --deep --options runtime --sign "$CODE_SIGN_IDENTITY" "$CW_RUNTIME_BUILD/frozen/Runtime.app"
codesign --verify --deep --strict "$CW_RUNTIME_BUILD/frozen/Runtime.app"
