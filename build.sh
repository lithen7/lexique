#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product Lexique

APP="/Applications/Lexique.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Lexique "$APP/Contents/MacOS/Lexique"
cp assets/icon-dock.svg.png "$APP/Contents/Resources/icon.png" 2>/dev/null || true
cp Resources/en_UK.txt Resources/en_US.txt "$APP/Contents/Resources/" 2>/dev/null || true
cp Vendor/OpenMDict/LICENSE "$APP/Contents/Resources/OpenMDict-LICENSE.txt" 2>/dev/null || true
cp Resources/LICENSE-ipa-dict.txt "$APP/Contents/Resources/" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lexique</string>
  <key>CFBundleDisplayName</key><string>Lexique</string>
  <key>CFBundleIdentifier</key><string>local.lexique</string>
  <key>CFBundleVersion</key><string>0.1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Lexique</string>
  <key>CFBundleIconFile</key><string>icon.png</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "built: $APP"
