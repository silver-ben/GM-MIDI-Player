#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="Release"
case "${1:-}" in
  ""|--release)
    CONFIGURATION="Release"
    ;;
  --debug)
    CONFIGURATION="Debug"
    ;;
  *)
    echo "Usage: ./scripts/build.sh [--release|--debug]" >&2
    exit 2
    ;;
esac

xcodebuild \
  -project GM-MIDI-AU.xcodeproj \
  -scheme GMDLSPlayerAU \
  -configuration "$CONFIGURATION" \
  -derivedDataPath build/DerivedData \
  -destination "generic/platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
