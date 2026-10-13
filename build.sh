#!/bin/bash
# Builds SpeakTyper.app (release) next to this script.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

APP="SpeakTyper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SpeakTyper" "$APP/Contents/MacOS/SpeakTyper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# SwiftPM resource bundles from dependencies (unused by ASR, but keeps Bundle.module happy).
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

# Ad-hoc sign so macOS privacy prompts (Mic / Accessibility) attach to the app.
codesign --force --deep --sign - \
  --requirements '=designated => identifier "com.local.speaktyper"' "$APP"
echo "Built $(pwd)/$APP"

# ./build.sh --install  → copy into /Applications and (re)launch from there.
if [[ "${1:-}" == "--install" ]]; then
  pkill -x SpeakTyper 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/$APP"
  cp -R "$APP" /Applications/
  open "/Applications/$APP"
  echo "Installed /Applications/$APP (it registers itself to launch at login)"
fi
