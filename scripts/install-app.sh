#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
uv sync --python 3.12 --extra dev
bash scripts/build-app.sh
mkdir -p "$HOME/Applications"
ditto --norsrc "build/Constant Watch.app" "$HOME/Applications/Constant Watch.app"
.venv/bin/python scripts/service.py install
echo "Installed $HOME/Applications/Constant Watch.app"
