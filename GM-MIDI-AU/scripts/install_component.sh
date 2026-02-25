#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build_release.sh

SOURCE_COMPONENT="build/DerivedData/Build/Products/Release/GM DLS Player.component"
TARGET_DIR="$HOME/Library/Audio/Plug-Ins/Components"
TARGET_COMPONENT="$TARGET_DIR/GM DLS Player.component"
TARGET_BINARY="$TARGET_COMPONENT/Contents/MacOS/GM DLS Player"

if [[ ! -d "$SOURCE_COMPONENT" ]]; then
  echo "Missing built component at: $SOURCE_COMPONENT" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_COMPONENT"
cp -R "$SOURCE_COMPONENT" "$TARGET_COMPONENT"
xattr -dr com.apple.quarantine "$TARGET_COMPONENT" 2>/dev/null || true

SIGN_IDENTITY="${GMDLS_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'\"' '/Developer ID Application:/{print $2; exit}')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'\"' '/Apple Development:/{print $2; exit}')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$TARGET_BINARY"
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$TARGET_COMPONENT"
else
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$TARGET_BINARY"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$TARGET_COMPONENT"
fi

codesign --verify --verbose=4 "$TARGET_BINARY"
codesign --verify --deep --strict "$TARGET_COMPONENT"

echo "Installed: $TARGET_COMPONENT"
echo "Signed with identity: $SIGN_IDENTITY"
