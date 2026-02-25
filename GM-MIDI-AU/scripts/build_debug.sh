#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

xcodebuild \
  -project GM-MIDI-AU.xcodeproj \
  -scheme GMDLSPlayerAU \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  -destination "generic/platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
