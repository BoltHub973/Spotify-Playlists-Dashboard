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
    # --git-common-dir is printed relative to SCRIPT_DIR (git's -C dir), so resolve
    # it from there — not from the caller's cwd, which may be anywhere.
    GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && cd "$GIT_COMMON_DIR" && pwd)"
    MAIN_REPO_ROOT="$(dirname "$GIT_COMMON_DIR")"
    BUILD_DIR="$MAIN_REPO_ROOT/desktop/SpotifyDashboard/build"
else
    # Fallback: write next to the script
    BUILD_DIR="$SCRIPT_DIR/build"
fi

# The repo root the installed app should run app.py / serve static files from.
# Prefer the main working tree (so a worktree build still points at the canonical
# checkout); fall back to two levels up from this script (repo root).
if [ -n "$MAIN_REPO_ROOT" ]; then
    PROJECT_ROOT_STAMP="$MAIN_REPO_ROOT"
else
    PROJECT_ROOT_STAMP="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

APP_NAME="Spotify Dashboard"
BUNDLE_NAME="SpotifyDashboard"
# Build into a staging dir, then install to /Applications (the canonical home).
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
INSTALL_DIR="/Applications"
INSTALLED_APP="$INSTALL_DIR/${APP_NAME}.app"

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

# Stamp commit-derived version metadata into the bundle's Info.plist.
# CFBundleShortVersionString stays as-is (managed by the app-versioning skill).
# CFBundleVersion + SpotifyDashboardVersionDisplay + SpotifyDashboardVersionCommitURL
# are computed from the same commit (latest origin/main), so the timestamp, SHA,
# and link all agree.
GIT_REF=$(git -C "$SCRIPT_DIR" rev-parse --verify origin/main 2>/dev/null \
       || git -C "$SCRIPT_DIR" rev-parse --verify main 2>/dev/null \
       || git -C "$SCRIPT_DIR" rev-parse HEAD)
GIT_TS_UNIX=$(git -C "$SCRIPT_DIR" log -1 --format='%ct' "$GIT_REF")
GIT_SHA=$(git -C "$SCRIPT_DIR" rev-parse --short=7 "$GIT_REF")
GIT_FULL_SHA=$(git -C "$SCRIPT_DIR" rev-parse "$GIT_REF")
BUILD_NUMBER=$(date -r "$GIT_TS_UNIX" +"%Y%m%d.%H%M")
DISPLAY_VERSION="$(date -r "$GIT_TS_UNIX" +"%m-%d-%y %-I:%M %p") · $GIT_SHA"

# Commit URL for the About-panel hyperlink. Derive the repo's https web URL from the
# origin remote (handles git@, ssh://, and https forms), then append the commit SHA.
# Stays empty when there's no origin remote — the About panel then shows plain text.
COMMIT_URL=""
REMOTE_URL=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")
if [ -n "$REMOTE_URL" ]; then
    WEB_URL=$(printf '%s' "$REMOTE_URL" \
        | sed -E 's#^git@([^:]+):#https://\1/#; s#^ssh://git@#https://#; s#\.git$##')
    COMMIT_URL="$WEB_URL/commit/$GIT_FULL_SHA"
fi

PLIST="$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :SpotifyDashboardVersionDisplay" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SpotifyDashboardVersionDisplay string $DISPLAY_VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :SpotifyDashboardVersionCommitURL" "$PLIST" 2>/dev/null || true
[ -n "$COMMIT_URL" ] && /usr/libexec/PlistBuddy -c "Add :SpotifyDashboardVersionCommitURL string $COMMIT_URL" "$PLIST"

# Stamp the project root so the app can find app.py / static/ even when launched
# from /Applications (where the bundle-relative path no longer resolves to the repo).
# BackendManager reads this as a fallback after the SPOTIFY_DASHBOARD_PATH env var.
/usr/libexec/PlistBuddy -c "Delete :SpotifyDashboardProjectRoot" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SpotifyDashboardProjectRoot string $PROJECT_ROOT_STAMP" "$PLIST"

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
echo "[3/5] Code signing..."
codesign --force --sign - "$APP_BUNDLE"

# Install into /Applications (the canonical, permanent location).
# Replacing a running bundle is safe — the live process keeps its open files and
# the new copy is used on next launch.
echo "[4/5] Installing to ${INSTALL_DIR}..."
if rm -rf "$INSTALLED_APP" 2>/dev/null && ditto "$APP_BUNDLE" "$INSTALLED_APP" 2>/dev/null; then
    codesign --force --sign - "$INSTALLED_APP" 2>/dev/null || true
    echo "Installed: $INSTALLED_APP"
    FINAL_APP="$INSTALLED_APP"
else
    echo "WARNING: could not write to ${INSTALL_DIR} (admin rights may be required)."
    echo "         The built app is available at: $APP_BUNDLE"
    echo "         To install manually: sudo ditto \"$APP_BUNDLE\" \"$INSTALLED_APP\""
    FINAL_APP="$APP_BUNDLE"
fi

echo "[5/5] Build complete!"
echo ""
echo "App bundle: $FINAL_APP"
echo "Size: $(du -sh "$FINAL_APP" | cut -f1)"
echo ""
echo "To run: open \"$FINAL_APP\""
echo "Or use: ./run.sh (from the desktop/ directory)"
