#!/bin/bash
# Builds a signed, self-contained Apple Silicon app and drag-install disk image.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${CODE_SIGN_IDENTITY+x}" ]]; then
  CW_DISTRIBUTION_IDS=($(security find-identity -v -p codesigning | awk '/"Developer ID Application: / {print $2}'))
  if [[ ${#CW_DISTRIBUTION_IDS[@]} -eq 1 ]]; then export CODE_SIGN_IDENTITY="${CW_DISTRIBUTION_IDS[0]}"; fi
fi
source scripts/signing.sh
export CW_BUNDLE_RUNTIME=1
bash scripts/build-app.sh
CW_PACKAGED_APP="$HOME/Library/Caches/Constant Watch/build/Constant Watch.app"
.venv/bin/python scripts/smoke-package.py "$CW_PACKAGED_APP"
bash scripts/package-dmg.sh
