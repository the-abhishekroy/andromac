#!/bin/zsh
# Adds the WidgetKit extension (Control Center + Notification Center widgets) to dist/Andromac.app.
# Run after ./build-app.sh.   Usage: ./build-widgets.sh [--install]
# Optional: TEAM_ID=XXXXXXXXXX (Apple Development cert from Xcode) to sign with a real identity instead of the local one.
set -e
cd "$(dirname "$0")"
APP=dist/Andromac.app
[ -d "$APP" ] || { echo "Run ./build-app.sh first"; exit 1; }
command -v xcodegen >/dev/null || { echo "brew install xcodegen"; exit 1; }
(cd Widgets && xcodegen generate -q && xcodebuild -project AndromacWidgets.xcodeproj -scheme AndromacWidgets -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build -quiet)
APPEX=Widgets/build/Build/Products/Release/AndromacWidgets.appex
[ -d "$APPEX" ] || { echo "appex build failed"; exit 1; }
rm -rf "$APP/Contents/PlugIns"; mkdir -p "$APP/Contents/PlugIns"
cp -R "$APPEX" "$APP/Contents/PlugIns/"
KC="$HOME/.andromac/signing/andromac-signing.keychain-db"
if [ -n "$TEAM_ID" ]; then
  ID=$(security find-identity -v -p codesigning | grep "Apple Development" | grep "($TEAM_ID)" | head -1 | awk '{print $2}')
  [ -n "$ID" ] || { echo "No Apple Development identity for team $TEAM_ID"; exit 1; }
  SIGN=(-s "$ID")
elif [ -f "$KC" ] && [ -f "$HOME/.andromac/signing/pw" ]; then
  security unlock-keychain -p "$(cat $HOME/.andromac/signing/pw)" "$KC"
  SIGN=(-s "Andromac Local Signing" --keychain "$KC")
else
  SIGN=(-s "${SIGN_ID:--}")
fi
codesign --force "${SIGN[@]}" --entitlements Widgets/Widgets.entitlements "$APP/Contents/PlugIns/AndromacWidgets.appex"
codesign --force "${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP" && echo "Built $APP with widgets"
if [ "$1" = "--install" ]; then
  pkill -x Andromac 2>/dev/null || true; pkill -x andromac-tunnel 2>/dev/null || true; sleep 1
  rm -rf /Applications/Andromac.app && cp -R "$APP" /Applications/Andromac.app && echo "Installed /Applications/Andromac.app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Andromac.app
  pluginkit -a /Applications/Andromac.app/Contents/PlugIns/AndromacWidgets.appex 2>/dev/null || true
  open /Applications/Andromac.app
fi
