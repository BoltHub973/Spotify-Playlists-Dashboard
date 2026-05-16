#!/bin/bash
#
# Build script for Spotify Dashboard macOS app
# Compiles Swift sources into a .app bundle using swiftc (no Xcode project required)
#
# Prerequisites: Xcode Command Line Tools (xcode-select --install)
#
# Usage: ./build.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES_DIR="$SCRIPT_DIR/Sources"
RESOURCES_DIR="$SCRIPT_DIR/Resources"

# Resolve the main repo root so builds from a worktree still land in the
# canonical desktop/SpotifyDashboard/build/ outside the worktree.
# `git rev-parse --git-common-dir` returns the shared .git dir; its parent is
# the main working tree's root.
GIT_COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --git-common-dir 2>/dev/null || true)"
if [ -n "$GIT_COMMON_DIR" ]; then
    # Normalize to absolute path, then take its parent
    GIT_COMMON_DIR="$(cd "$GIT_COMMON_DIR" && pwd)"
    MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
    BUILD_DIR="$MAIN_REPO_ROOT/desktop/SpotifyDashboard/build"
else
    # Fallback: write next to the script
    BUILD_DIR="$SCRIPT_DIR/build"
fi
APP_NAME="Spotify Dashboard"
BUNDLE_NAME="SpotifyDashboard"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"

echo "=== Building ${APP_NAME} ==="
echo ""

# Clean previous build
rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"

# Create .app bundle structure
echo "[1/4] Creating app bundle structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$RESOURCES_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Copy AppleScript dictionary
cp "$RESOURCES_DIR/SpotifyDashboard.sdef" "$APP_BUNDLE/Contents/Resources/"

# Copy app icon
if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Create PkgInfo
echo -n "APPLSPDH" > "$APP_BUNDLE/Contents/PkgInfo"

# Compile Swift sources
echo "[2/4] Compiling Swift sources..."
SWIFT_FILES=(
    "$SOURCES_DIR/main.swift"
    "$SOURCES_DIR/AppDelegate.swift"
    "$SOURCES_DIR/MainWindowController.swift"
    "$SOURCES_DIR/BackendManager.swift"
    "$SOURCES_DIR/LoadingViewController.swift"
    "$SOURCES_DIR/MissingFilesViewController.swift"
    "$SOURCES_DIR/AuthRequiredViewController.swift"
    "$SOURCES_DIR/StatusBarController.swift"
    "$SOURCES_DIR/HotkeyManager.swift"
    "$SOURCES_DIR/ShortcutRecorderView.swift"
    "$SOURCES_DIR/SettingsWindowController.swift"
    "$SOURCES_DIR/AppleScriptCommands.swift"
)

swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/$BUNDLE_NAME" \
    -module-name "$BUNDLE_NAME" \
    -framework Cocoa \
    -framework WebKit \
    -framework Carbon \
    -target "$(uname -m)-apple-macosx11.0" \
    -O \
    "${SWIFT_FILES[@]}"

# Ad-hoc code sign
echo "[3/4] Code signing..."
codesign --force --sign - "$APP_BUNDLE"

echo "[4/4] Build complete!"
echo ""
echo "App bundle: $APP_BUNDLE"
echo "Size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""
echo "To run: open \"$APP_BUNDLE\""
echo "Or use: ./run.sh (from the desktop/ directory)"
