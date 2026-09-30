#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing.sh
bash scripts/build-native.sh
if [[ "${CW_BUNDLE_RUNTIME:-0}" == "1" ]]; then bash scripts/build-runtime.sh; fi
APP="$HOME/Library/Caches/Constant Watch/build/Constant Watch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.constantwatch.app</string>
<key>CFBundleName</key><string>Constant Watch</string>
<key>CFBundleDisplayName</key><string>Constant Watch</string>
<key>CFBundleExecutable</key><string>ConstantWatch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Record your voice when you choose to record a meeting. Transcription runs on this Mac.</string>
<key>NSScreenCaptureUsageDescription</key><string>Read visible text to build your private local screen journal.</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Constant Watch</string><key>CFBundleURLSchemes</key><array><string>constantwatch</string></array></dict></array>
</dict></plist>
PLIST
swiftc -parse-as-library -O -target arm64-apple-macosx14.0 native/App.swift native/Design.swift native/RecallViews.swift native/ReviewViews.swift native/Onboarding.swift native/OnboardingVisuals.swift native/LogoReveal.swift native/BrandMark.swift native/CaptureCore.swift native/MeetingRecorder.swift native/MeetingViews.swift -o "$APP/Contents/MacOS/ConstantWatch" -framework SwiftUI -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit -framework Vision -framework AVFoundation -framework WebKit
ditto --norsrc "$HOME/Library/Caches/Constant Watch/build/Constant Watch Capture.app" "$APP/Contents/Helpers/Constant Watch Capture.app"
if [[ "${CW_BUNDLE_RUNTIME:-0}" == "1" ]]; then
    # Replace only generated staging content, preventing stale runtime files in updates.
    rm -rf "$APP/Contents/Helpers/Runtime" "$APP/Contents/Helpers/Runtime.app"
    ditto --norsrc "$HOME/Library/Caches/Constant Watch/packaging/frozen/Runtime.app" "$APP/Contents/Helpers/Runtime.app"
    .venv/bin/python scripts/third-party-notices.py "$APP/Contents/Resources/Third-party notices.txt"
fi
cp native/Resources/OnboardingAmbience.wav "$APP/Contents/Resources/OnboardingAmbience.wav"
cp src/constant_watch/static/assets/alpine-hero.jpg "$APP/Contents/Resources/AlpineHero.jpg"
swiftc -parse-as-library native/BrandMark.swift scripts/make-icon.swift -o build/make-icon -framework SwiftUI -framework AppKit
./build/make-icon
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --deep --options runtime --sign "$CODE_SIGN_IDENTITY" --identifier local.constantwatch.app --entitlements scripts/app-entitlements.plist "$APP"
rm -rf "build/Constant Watch.app"
ditto --norsrc "$APP" "build/Constant Watch.app"
echo "Built $APP"
