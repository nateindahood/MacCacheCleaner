#!/bin/bash
set -e

# Builds the app and packages it into a drag-to-Applications DMG in dist/

APP_NAME="MacCacheCleaner"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
DMG_PATH="dist/$APP_NAME-$VERSION.dmg"

./build.sh

# Staged outside iCloud Drive so its extended attributes don't end up in the image
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "build/$APP_NAME.app" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p dist
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING_DIR" \
    -fs HFS+ -format UDZO -ov "$DMG_PATH" >/dev/null

echo ""
echo "DMG created: $DMG_PATH"
