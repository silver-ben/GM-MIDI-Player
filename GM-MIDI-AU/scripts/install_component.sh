#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build.sh --release

SOURCE_COMPONENT="build/DerivedData/Build/Products/Release/GM DLS Player.component"
TARGET_DIR="$HOME/Library/Audio/Plug-Ins/Components"
TARGET_COMPONENT="$TARGET_DIR/GM DLS Player.component"

if [[ ! -d "$SOURCE_COMPONENT" ]]; then
  echo "Missing built component at: $SOURCE_COMPONENT" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_COMPONENT"
cp -R "$SOURCE_COMPONENT" "$TARGET_COMPONENT"
xattr -cr "$TARGET_COMPONENT" 2>/dev/null || true

echo "Installed: $TARGET_COMPONENT"
echo "Installation mode: unsigned (not notarized)"
echo "If macOS blocks loading, run:"
echo "  xattr -cr \"$TARGET_COMPONENT\""
