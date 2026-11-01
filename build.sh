#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 duderayuh
# Build MINI-5 Forge into a signed .app bundle. No Xcode project, no SwiftPM needed.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MINI-5 Forge"
BUNDLE_ID="com.duderayuh.mini5forge"
OUT="build/MINI-5 Forge.app"
INSTALLED="$HOME/Applications/MINI-5 Forge.app"
SDK_TARGET="arm64-apple-macos13.0"

mkdir -p build

echo "== compiling =="
swiftc -parse-as-library -O -target "$SDK_TARGET" \
  -o build/Mini5Forge \
  $(find Sources/Mini5Core Sources/Mini5Forge -name '*.swift')

echo "== compiling selftest =="
swiftc -O -target "$SDK_TARGET" -o build/mini5forge-selftest \
  $(find Sources/Mini5Core -name '*.swift') Sources/SelfTest/main.swift

echo "== bundling =="
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp build/Mini5Forge "$OUT/Contents/MacOS/Mini5Forge"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>Mini5Forge</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>MINI-5 Forge talks to your Baofeng radio over Bluetooth to read, edit and write its channel configuration. Nothing leaves this Mac.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>MINI-5 Forge talks to your Baofeng radio over Bluetooth to program its channels.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Local utility. Protocol documented from public reverse-engineering.</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$OUT/Contents/PkgInfo"

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
fi

echo "== signing =="
codesign --force --sign - --timestamp=none "$OUT" 2>&1 | tail -2 || true

echo "== done: $OUT =="
ls -la "$OUT/Contents/MacOS/"

# ---- install ----
# Build straight to the user Applications folder and remove the staging copy, so
# exactly one bundle with this identifier exists on disk. Two bundles sharing a
# bundle id show up as duplicate apps in Launchpad and Spotlight.
mkdir -p "$HOME/Applications"
rm -rf "$INSTALLED"
ditto "$OUT" "$INSTALLED" || exit 1
rm -rf "$OUT"
rmdir build 2>/dev/null
echo "| installed $INSTALLED"
# no duplicate bundle left in build/
