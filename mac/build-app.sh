#!/bin/zsh
# Builds dist/Andromac.app (works with just the Command Line Tools).
set -e
cd "$(dirname "$0")"
if [ ! -x ../tunnel/build/andromac-tunnel ]; then (cd ../tunnel && PATH=/opt/homebrew/bin:$PATH go build -o build/andromac-tunnel ./cmd/andromac-tunnel); fi
swift build -c release --product Andromac
APP=dist/Andromac.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Andromac "$APP/Contents/MacOS/Andromac"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp ../tunnel/build/andromac-tunnel "$APP/Contents/Resources/andromac-tunnel"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.andromac.mac</string>
  <key>CFBundleName</key><string>Andromac</string>
  <key>CFBundleDisplayName</key><string>Andromac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>Andromac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSScreenCaptureUsageDescription</key><string>Andromac shares your screen with your phone only when you approve it.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
# Sign with the stable local identity when it exists, so macOS privacy permissions (Screen Recording,
# Accessibility, Full Disk Access) survive rebuilds. Falls back to ad-hoc signing.
KC="$HOME/.andromac/signing/andromac-signing.keychain-db"
if [ -f "$KC" ] && [ -f "$HOME/.andromac/signing/pw" ]; then
  security unlock-keychain -p "$(cat $HOME/.andromac/signing/pw)" "$KC"
  codesign --force --deep -s "Andromac Local Signing" --keychain "$KC" "$APP"
else
  codesign --force --deep -s "${SIGN_ID:--}" "$APP"
fi
echo "Built $APP"
if [ "$1" = "--install" ]; then
  pkill -x Andromac 2>/dev/null || true; pkill -x andromac-tunnel 2>/dev/null || true; sleep 1
  rm -rf /Applications/Andromac.app && cp -R "$APP" /Applications/Andromac.app && echo "Installed /Applications/Andromac.app"
fi
