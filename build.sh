#!/bin/bash
# 編譯出 番茄鐘.app。需要 Xcode Command Line Tools（xcode-select --install）。
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="番茄鐘"
BUNDLE_ID="local.pomodoro.timer"
OUT="${1:-$PWD}"                 # 第一個參數可指定輸出資料夾，預設是專案目錄
APP="$OUT/$APP_NAME.app"
BUILD=".build"

echo "▸ 清理"
rm -rf "$APP" "$BUILD"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ 編譯"
swiftc -O -whole-module-optimization \
    -o "$APP/Contents/MacOS/$APP_NAME" \
    Sources/*.swift

echo "▸ 產生圖示"
swift Tools/MakeIcon.swift "$BUILD/icon.iconset" >/dev/null
iconutil -c icns "$BUILD/icon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ 寫入 Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string></string>
</dict>
</plist>
PLIST

echo "▸ 簽章"
codesign --force --deep --sign - "$APP"

echo "✅ 完成：$APP"
