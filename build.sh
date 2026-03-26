#!/usr/bin/env bash
# Build Context Pressure menu bar app without Xcode IDE.
# Requires: Xcode Command Line Tools (xcode-select --install)
#
# Usage:
#   ./build.sh              Build the app
#   ./build.sh --run        Build and run
#   ./build.sh --install    Build and install to /Applications
#   ./build.sh --clean      Remove build artifacts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/ContextPressure"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="Context Pressure"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
EXECUTABLE="ContextPressure"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Clean ────────────────────────────────────────────────────
if [[ "${1:-}" == "--clean" ]]; then
    rm -rf "$BUILD_DIR"
    echo -e "${GREEN}Cleaned build directory.${RESET}"
    exit 0
fi

# ─── Preflight ────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}Building ${APP_NAME}...${RESET}"
echo ""

if ! command -v swiftc &>/dev/null; then
    echo -e "${RED}Error: Swift compiler not found.${RESET}"
    echo "Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

SWIFT_VERSION=$(swiftc --version 2>&1 | head -1)
echo -e "  ${GREEN}✓${RESET} $SWIFT_VERSION"

# Check macOS version (need 13+ for MenuBarExtra)
MACOS_VERSION=$(sw_vers -productVersion)
MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [[ $MAJOR -lt 13 ]]; then
    echo -e "${RED}Error: macOS 13 (Ventura) or later is required.${RESET}"
    echo "  You have macOS $MACOS_VERSION"
    exit 1
fi
echo -e "  ${GREEN}✓${RESET} macOS $MACOS_VERSION"

# ─── Collect source files ─────────────────────────────────────
SOURCES=$(find "$SRC_DIR" -name "*.swift" -type f)
SOURCE_COUNT=$(echo "$SOURCES" | wc -l | tr -d ' ')
echo -e "  ${GREEN}✓${RESET} Found $SOURCE_COUNT Swift source files"

# ─── Create app bundle structure ──────────────────────────────
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$SRC_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# ─── Compile ──────────────────────────────────────────────────
echo ""
echo -e "  Compiling..."

swiftc \
    -target arm64-apple-macosx13.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework SwiftUI \
    -framework AppKit \
    -framework UserNotifications \
    -parse-as-library \
    -O \
    -o "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE" \
    $SOURCES \
    2>&1

# Also build for x86_64 if on Apple Silicon (universal binary)
if [[ "$(uname -m)" == "arm64" ]]; then
    echo -e "  Building universal binary (arm64 + x86_64)..."

    swiftc \
        -target x86_64-apple-macosx13.0 \
        -sdk "$(xcrun --show-sdk-path)" \
        -framework SwiftUI \
        -framework AppKit \
        -framework UserNotifications \
        -parse-as-library \
        -O \
        -o "$BUILD_DIR/${EXECUTABLE}_x86" \
        $SOURCES \
        2>&1

    # Create universal binary
    lipo -create \
        "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE" \
        "$BUILD_DIR/${EXECUTABLE}_x86" \
        -output "$APP_BUNDLE/Contents/MacOS/${EXECUTABLE}_universal"

    mv "$APP_BUNDLE/Contents/MacOS/${EXECUTABLE}_universal" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
    rm -f "$BUILD_DIR/${EXECUTABLE}_x86"

    echo -e "  ${GREEN}✓${RESET} Universal binary created"
fi

# ─── Sign ─────────────────────────────────────────────────────
echo -e "  Signing..."
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
echo -e "  ${GREEN}✓${RESET} Ad-hoc signed"

# ─── Done ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  Build successful!${RESET}"
echo -e "  App: ${APP_BUNDLE}"
APP_SIZE=$(du -sh "$APP_BUNDLE" | awk '{print $1}')
echo -e "  Size: $APP_SIZE"
echo ""

# ─── Run or Install ──────────────────────────────────────────
case "${1:-}" in
    --run)
        echo -e "  Launching ${APP_NAME}..."
        open "$APP_BUNDLE"
        ;;
    --install)
        DEST="/Applications/${APP_NAME}.app"
        if [[ -d "$DEST" ]]; then
            echo -e "  ${YELLOW}Replacing existing installation...${RESET}"
            rm -rf "$DEST"
        fi
        cp -R "$APP_BUNDLE" "$DEST"
        echo -e "  ${GREEN}✓${RESET} Installed to /Applications"
        echo ""
        echo "  The app will appear in your menu bar (top-right)."
        echo "  It runs as a background app — no Dock icon."
        echo ""
        echo "  To launch: open '${DEST}'"
        echo "  To auto-start: System Settings > General > Login Items > add '${APP_NAME}'"
        ;;
    *)
        echo "  To run:     ./build.sh --run"
        echo "  To install: ./build.sh --install"
        echo "  To clean:   ./build.sh --clean"
        ;;
esac
