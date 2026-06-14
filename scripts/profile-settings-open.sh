#!/usr/bin/env bash
set -euo pipefail

# Records a Time Profiler trace, triggers Settings with Cmd+, and exports TOC/signpost XML.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${1:-$HOME/Desktop}"
SCHEME="TinyClips"
TIME_LIMIT_SECONDS="${TIME_LIMIT_SECONDS:-30}"

mkdir -p "$OUTPUT_DIR"

STAMP=$(date +%Y%m%d-%H%M%S)
TRACE_PATH="$OUTPUT_DIR/tinyclips-settings-$STAMP.timeprof.trace"
TOC_PATH="$OUTPUT_DIR/tinyclips-settings-$STAMP.toc.xml"
SIGNPOSTS_PATH="$OUTPUT_DIR/tinyclips-settings-$STAMP.signposts.xml"

cd "$ROOT_DIR"
echo "Building $SCHEME (Debug)..."
xcodebuild build -project mac/TinyClips.xcodeproj -scheme "$SCHEME" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO >/dev/null

APP_PATH=$(find "$HOME"/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Debug/TinyClips.app" -print -quit 2>/dev/null || true)
if [[ -z "$APP_PATH" ]]; then
  echo "Could not locate Debug TinyClips.app in DerivedData after build."
  exit 1
fi

echo "Recording Time Profiler trace: $TRACE_PATH"
xcrun xctrace record --template "Time Profiler" --time-limit "${TIME_LIMIT_SECONDS}s" --output "$TRACE_PATH" --launch -- "$APP_PATH" &
RECORD_PID=$!

# Give launch time, then open Settings while recording.
sleep 5
osascript -e 'tell application "TinyClips" to activate' \
          -e 'delay 1' \
          -e 'tell application "System Events" to keystroke "," using command down' >/dev/null 2>&1 || true

# xctrace can return a non-zero status when it terminates the launched app at the time limit.
wait "$RECORD_PID" || true

echo "Exporting TOC: $TOC_PATH"
xcrun xctrace export --input "$TRACE_PATH" --toc > "$TOC_PATH"

echo "Exporting os-signpost table: $SIGNPOSTS_PATH"
xcrun xctrace export --input "$TRACE_PATH" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' > "$SIGNPOSTS_PATH"

echo

echo "Artifacts:"
echo "- $TRACE_PATH"
echo "- $TOC_PATH"
echo "- $SIGNPOSTS_PATH"
echo

echo "Matched signposts (if present):"
grep -n 'SettingsOpen\|VideoSettingsTabOpened\|MicrophoneEnumeration' "$SIGNPOSTS_PATH" || true
