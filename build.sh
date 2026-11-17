#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${KEYTONE_BUILD_DIR:-.build}"
APP="${KEYTONE_APP_PATH:-dist/KeyTone.app}"
APP_VERSION="$(tr -d '\r\n' < VERSION)"
APP_BUILD="$(tr -d '\r\n' < BUILD_NUMBER)"
SOURCE_REVISION="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
if ! git diff --quiet HEAD -- 2>/dev/null; then SOURCE_REVISION="$SOURCE_REVISION+dirty"; fi
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
[[ "$APP_BUILD" =~ ^[0-9]+$ ]] || exit 2
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun clang -std=c11 -O3 -mmacosx-version-min=13.0 -arch arm64 -c Sources/AudioCore.c -o "$BUILD/AudioCore.o"
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/AudioCore.h Sources/Localization.swift Sources/PressFilter.swift Sources/KeyMonitor.swift Sources/AppModel.swift Sources/Views.swift Sources/main.swift "$BUILD/AudioCore.o" -framework Cocoa -framework SwiftUI -framework AVFoundation -framework AudioToolbox -framework CoreAudio -framework Carbon -framework ServiceManagement -o "$APP/Contents/MacOS/KeyTone"
# Clean only this generated app's resource directory so retired sound files do not persist.
if [[ -d "$APP/Contents/Resources/Sounds" ]]; then
    find "$APP/Contents/Resources/Sounds" -maxdepth 1 -type f -name '*.wav' -delete
fi
cp -R Resources/. "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE-KeyTone.txt"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>KeyTone</string>
<key>CFBundleIdentifier</key><string>local.keytone.app</string>
<key>CFBundleName</key><string>KeyTone</string>
<key>CFBundleDisplayName</key><string>KeyTone</string>
<key>CFBundleIconFile</key><string>KeyTone.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_BUILD</string>
<key>KeyToneSourceRevision</key><string>$SOURCE_REVISION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>KeyTone · Audio recordings from Mechvibes, MIT license. See SOURCES.md.</string>
</dict></plist>
PLIST
python3 scripts/sign_app.py "$APP"
codesign --verify --deep --strict "$APP"
