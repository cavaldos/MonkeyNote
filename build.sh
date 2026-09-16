#!/bin/bash

# MonkeyNote Build Script
# This script builds the app and creates a DMG file in the release folder

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
RELEASE_DIR="$PROJECT_DIR/release"
APP_NAME="MonkeyNote"
DMG_NAME="$APP_NAME.dmg"
DESTINATION="platform=macOS,arch=arm64"
# Ad-hoc sign so the DMG works on any Mac without your Developer ID cert
SIGN_ARGS='CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='
# Parity with CI (release.yml exports these from the tag): honor exported
# MARKETING_VERSION / CURRENT_PROJECT_VERSION so About shows the same numbers,
# otherwise fall back to the values baked into the Xcode project.
VERSION_ARGS=()

# Optional version override: ./build.sh v1.3.5
# Injects MARKETING_VERSION into the build (same mechanism as CI),
# so Settings → About shows the given version instead of the
# hardcoded one in project.pbxproj.
if [ $# -ge 1 ]; then
    VERSION="${1#v}"
    if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Version '$1' must look like vX.Y.Z (e.g. ./build.sh v1.3.5)${NC}"
        exit 1
    fi
    # Mirror CI (run number); locally there is no run number,
    # so use the commit count to keep the build number increasing.
    BUILD_NUMBER=$(( $(git rev-list --count HEAD) ))
    echo -e "${YELLOW}Version override: $VERSION ($BUILD_NUMBER)${NC}"
    echo ""
    VERSION_ARGS=(MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
elif [ -n "${MARKETING_VERSION:-}" ]; then
    VERSION_ARGS=(MARKETING_VERSION="$MARKETING_VERSION")
    if [ -n "${CURRENT_PROJECT_VERSION:-}" ]; then
        VERSION_ARGS+=(CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION")
    fi
fi

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}   MonkeyNote Build Script${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Step 1: Clean release folder
echo -e "${YELLOW}[1/5] Preparing release folder...${NC}"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Step 2: Build the app
echo -e "${YELLOW}[2/5] Building $APP_NAME (Release)...${NC}"
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "$DESTINATION" \
    $SIGN_ARGS \
    "${VERSION_ARGS[@]}" \
    clean build

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Build succeeded!${NC}"

# Step 3: Find the built app
echo -e "${YELLOW}[3/5] Locating built app...${NC}"
BUILD_DIR=$(xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "$DESTINATION" \
    "${VERSION_ARGS[@]}" \
    -showBuildSettings 2>/dev/null | sed -n 's/^ *BUILT_PRODUCTS_DIR *= *//p' | head -1)

APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: Built app not found at $APP_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}Found app at: $APP_PATH${NC}"

# Step 4: Re-sign (fixes dyld "different Team IDs" crash on embedded frameworks)
echo -e "${YELLOW}[4/5] Re-signing app (ad-hoc)...${NC}"
codesign --force --deep --sign - "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"
if [ $? -ne 0 ]; then
    echo -e "${RED}Signature verification failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Signature OK!${NC}"

# Step 5: Create DMG
echo -e "${YELLOW}[5/5] Creating DMG...${NC}"
TMP_DIR=$(mktemp -d)
# ditto (not cp -R) preserves symlinks, signatures and resource forks
ditto "$APP_PATH" "$TMP_DIR/$APP_NAME.app"
ln -sf /Applications "$TMP_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$RELEASE_DIR/$DMG_NAME"

DMG_STATUS=$?
rm -rf "$TMP_DIR"

if [ $DMG_STATUS -ne 0 ]; then
    echo -e "${RED}Failed to create DMG!${NC}"
    exit 1
fi

# Done
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "DMG file: ${GREEN}$RELEASE_DIR/$DMG_NAME${NC}"
echo ""

# Show file size
DMG_SIZE=$(ls -lh "$RELEASE_DIR/$DMG_NAME" | awk '{print $5}')
echo -e "Size: ${GREEN}$DMG_SIZE${NC}"
echo ""

# Open release folder (skip on CI runners — headless)
if [ -z "${CI:-}" ]; then
    open "$RELEASE_DIR"
fi
