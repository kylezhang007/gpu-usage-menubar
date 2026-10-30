#!/bin/bash
# Builds GPUUsage.app (Apple Silicon + Intel) and a zip you can copy to another Mac.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/GPUUsage.app"
rm -rf build && mkdir -p build

swift build -c release --triple arm64-apple-macosx14.0
BINS=(".build/arm64-apple-macosx/release/GPUUsage")
if swift build -c release --triple x86_64-apple-macosx14.0 >/dev/null 2>&1; then
  BINS+=(".build/x86_64-apple-macosx/release/GPUUsage")
else
  echo "Intel build skipped; the app will run on Apple Silicon only."
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/GPUUsage"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GPUUsage</string>
  <key>CFBundleDisplayName</key><string>GPU 用量</string>
  <key>CFBundleIdentifier</key><string>com.local.gpuusage</string>
  <key>CFBundleExecutable</key><string>GPUUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
ditto -c -k --keepParent "$APP" build/GPUUsage.zip
echo "Built $APP and build/GPUUsage.zip ($(lipo -archs "$APP/Contents/MacOS/GPUUsage"))"
