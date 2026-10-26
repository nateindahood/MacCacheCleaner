#!/bin/bash
set -e

APP_NAME="MacCacheCleaner"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# The project lives in iCloud Drive, which tags files with extended attributes that
# codesign rejects, so the bundle is assembled and signed in a temp folder first
STAGING_DIR="$(mktemp -d)"
STAGED_BUNDLE="$STAGING_DIR/$APP_NAME.app"
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "Building $APP_NAME..."

# Clean previous build
rm -rf "$BUILD_DIR"

# Create .app bundle structure
mkdir -p "$STAGED_BUNDLE/Contents/MacOS"
mkdir -p "$STAGED_BUNDLE/Contents/Resources"

# Compile all Swift sources
swiftc -o "$STAGED_BUNDLE/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macosx13.0 \
    -framework SwiftUI \
    -framework AppKit \
    -O \
    -whole-module-optimization \
    Sources/*.swift

# Copy Info.plist and app icon
cp Info.plist "$STAGED_BUNDLE/Contents/"
cp Resources/AppIcon.icns "$STAGED_BUNDLE/Contents/Resources/"

# Create PkgInfo
echo -n "APPL????" > "$STAGED_BUNDLE/Contents/PkgInfo"

# Ad-hoc sign the whole bundle so macOS privacy permissions attach to the app
xattr -cr "$STAGED_BUNDLE"
codesign --force --sign - --identifier com.nateindahood.maccachecleaner "$STAGED_BUNDLE"

mkdir -p "$BUILD_DIR"
ditto "$STAGED_BUNDLE" "$APP_BUNDLE"

echo ""
echo "Build successful!"
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run:     open $APP_BUNDLE"
echo "To install: ditto $APP_BUNDLE /Applications/$APP_NAME.app"
