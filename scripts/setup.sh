#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
uv sync --python 3.12 --extra dev
bash scripts/build-native.sh
ollama pull qwen3.5:0.8b
.venv/bin/constant-watch doctor
