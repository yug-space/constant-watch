#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing.sh
APP="$HOME/Library/Caches/Constant Watch/build/Constant Watch Capture.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.constantwatch.capture</string>
<key>CFBundleName</key><string>Constant Watch Capture</string>
<key>CFBundleExecutable</key><string>capture</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>Read visible text for your private local screen journal.</string>
</dict></plist>
PLIST
swiftc -parse-as-library -O -target arm64-apple-macosx14.0 native/Capture.swift native/CaptureCore.swift -o "$APP/Contents/MacOS/capture" -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit -framework Vision
xattr -cr "$APP"
codesign --force --deep --sign "$CODE_SIGN_IDENTITY" --identifier local.constantwatch.capture "$APP"
mkdir -p build
ditto --norsrc "$APP" "build/Constant Watch Capture.app"
echo "Built $APP"
