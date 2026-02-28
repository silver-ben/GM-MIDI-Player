#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build.sh --release

SOURCE_COMPONENT="build/DerivedData/Build/Products/Release/GM DLS Player.component"
RELEASE_DIR="build/release"
STAGE_DIR="$RELEASE_DIR/stage"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || true)"
fi
if [[ -z "$VERSION" ]]; then
  VERSION="dev"
fi

if [[ ! -d "$SOURCE_COMPONENT" ]]; then
  echo "Missing built component at: $SOURCE_COMPONENT" >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

STAGED_COMPONENT="$STAGE_DIR/GM DLS Player.component"
cp -R "$SOURCE_COMPONENT" "$STAGED_COMPONENT"
# Keep Finder bundle metadata so .component is shown as a package, only clear quarantine if present.
xattr -dr com.apple.quarantine "$STAGED_COMPONENT" 2>/dev/null || true

ARTIFACT_BASENAME="GM-DLS-Player-v${VERSION}"
DMG_PATH="$RELEASE_DIR/${ARTIFACT_BASENAME}.dmg"
CHECKSUM_PATH="$RELEASE_DIR/${ARTIFACT_BASENAME}.dmg.sha256.txt"

rm -f "$DMG_PATH" "$CHECKSUM_PATH"

hdiutil create \
  -volname "GM DLS Player v${VERSION}" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

rm -rf "$STAGE_DIR"

echo "Created artifact: $DMG_PATH"
echo "Created checksum: $CHECKSUM_PATH"
echo "Release mode: unsigned (not notarized)"
