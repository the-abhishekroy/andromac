#!/bin/zsh
# Builds dist/Andromac-<version>.dmg (run ./build-app.sh first).
set -e
cd "$(dirname "$0")"
[ -d dist/Andromac.app ] || ./build-app.sh
[ -d .venv-dmg ] || { python3 -m venv .venv-dmg && .venv-dmg/bin/pip install -q dmgbuild pillow; }
.venv-dmg/bin/python dmg/make-background.py
tiffutil -cathidpicheck dmg/background.png dmg/background@2x.png -out dmg/background.tiff
VER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Andromac.app/Contents/Info.plist)
OUT="dist/Andromac-$VER.dmg"; rm -f "$OUT"
.venv-dmg/bin/dmgbuild -s dmg/settings.py "Andromac" "$OUT"
echo "Built $OUT"
