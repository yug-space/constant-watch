#!/bin/bash
# Package an already built and signed app, preserving its code signature.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${CODE_SIGN_IDENTITY+x}" ]]; then
  CW_DISTRIBUTION_IDS=($(security find-identity -v -p codesigning | awk '/"Developer ID Application: / {print $2}'))
  if [[ ${#CW_DISTRIBUTION_IDS[@]} -eq 1 ]]; then export CODE_SIGN_IDENTITY="${CW_DISTRIBUTION_IDS[0]}"; fi
fi
source scripts/signing.sh
CW_VERSION=$(.venv/bin/python -c 'import tomllib; print(tomllib.load(open("pyproject.toml", "rb"))["project"]["version"])')
CW_PACKAGED_APP="$HOME/Library/Caches/Constant Watch/build/Constant Watch.app"
codesign --verify --deep --strict "$CW_PACKAGED_APP"
CW_STAGE=$(mktemp -d "$HOME/Library/Caches/Constant Watch/packaging/dmg-stage.XXXXXX")
trap 'rm -rf "$CW_STAGE"' EXIT
mkdir -p dist
cp docs/INSTALL.txt "$CW_STAGE/Read me first.txt"
.venv/bin/python scripts/third-party-notices.py "$CW_STAGE/Third-party notices.txt"
swift scripts/make-installer-background.swift "$CW_STAGE/installer-background"
tiffutil -cathidpicheck "$CW_STAGE/installer-background.png" "$CW_STAGE/installer-background@2x.png" -out "$CW_STAGE/installer-background.tiff"
CW_DMG="$PWD/dist/Constant-Watch-${CW_VERSION}-macOS-arm64.dmg"
.venv/bin/dmgbuild -s scripts/dmg-settings.py -D "stage=$CW_STAGE" -D "app=$CW_PACKAGED_APP" 'Constant Watch' "$CW_DMG"
codesign --force --sign "$CODE_SIGN_IDENTITY" "$CW_DMG"
if [[ -n "${CW_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$CW_DMG" --keychain-profile "$CW_NOTARY_PROFILE" --wait
  xcrun stapler staple "$CW_DMG"
  xcrun stapler validate "$CW_DMG"
fi
hdiutil verify "$CW_DMG"
(cd dist && shasum -a 256 "$(basename "$CW_DMG")" > "$(basename "$CW_DMG").sha256")
if [[ -n "${CW_NOTARY_PROFILE:-}" ]]; then
  printf 'Signed and notarized. Apple Silicon, macOS 14+.\n' > dist/RELEASE-STATUS.txt
else
  printf 'Signed preview. Not notarized. Apple Silicon, macOS 14+.\nNot yet ready for frictionless distribution to other Macs.\n' > dist/RELEASE-STATUS.txt
fi
printf 'Packaged: %s\n' "$CW_DMG"
