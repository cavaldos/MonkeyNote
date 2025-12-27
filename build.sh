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

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}   MonkeyNote Build Script${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Step 1: Clean release folder
echo -e "${YELLOW}[1/4] Preparing release folder...${NC}"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Step 2: Build the app
echo -e "${YELLOW}[2/4] Building $APP_NAME (Release)...${NC}"
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    clean build \
    -quiet

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Build succeeded!${NC}"

# Step 3: Find the built app
echo -e "${YELLOW}[3/4] Locating built app...${NC}"
BUILD_DIR=$(xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -showBuildSettings 2>/dev/null | grep -m 1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')

APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: Built app not found at $APP_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}Found app at: $APP_PATH${NC}"

# Step 4: Create DMG
echo -e "${YELLOW}[4/4] Creating DMG...${NC}"
TMP_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$TMP_DIR/"
ln -sf /Applications "$TMP_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$RELEASE_DIR/$DMG_NAME" \
    -quiet

rm -rf "$TMP_DIR"

if [ $? -ne 0 ]; then
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

# Open release folder
open "$RELEASE_DIR"
