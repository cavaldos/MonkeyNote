#!/bin/bash

# Download Ripgrep for MonkeyNote
# This script downloads the ripgrep binary and creates a universal binary for macOS

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
RG_VERSION="14.1.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/MonkeyNote/Resources/bin"
TEMP_DIR=$(mktemp -d)

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}   Ripgrep Downloader for MonkeyNote${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "Version: ${GREEN}$RG_VERSION${NC}"
echo ""

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Download URLs
ARM64_URL="https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-aarch64-apple-darwin.tar.gz"
X86_64_URL="https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-x86_64-apple-darwin.tar.gz"

echo -e "${YELLOW}[1/4] Downloading ARM64 binary...${NC}"
curl -sL "$ARM64_URL" -o "$TEMP_DIR/rg-arm64.tar.gz"
tar -xzf "$TEMP_DIR/rg-arm64.tar.gz" -C "$TEMP_DIR"
ARM64_BIN="$TEMP_DIR/ripgrep-${RG_VERSION}-aarch64-apple-darwin/rg"

if [ ! -f "$ARM64_BIN" ]; then
    echo -e "${RED}Failed to download ARM64 binary${NC}"
    exit 1
fi
echo -e "${GREEN}ARM64 binary downloaded${NC}"

echo -e "${YELLOW}[2/4] Downloading x86_64 binary...${NC}"
curl -sL "$X86_64_URL" -o "$TEMP_DIR/rg-x86_64.tar.gz"
tar -xzf "$TEMP_DIR/rg-x86_64.tar.gz" -C "$TEMP_DIR"
X86_64_BIN="$TEMP_DIR/ripgrep-${RG_VERSION}-x86_64-apple-darwin/rg"

if [ ! -f "$X86_64_BIN" ]; then
    echo -e "${RED}Failed to download x86_64 binary${NC}"
    exit 1
fi
echo -e "${GREEN}x86_64 binary downloaded${NC}"

echo -e "${YELLOW}[3/4] Creating Universal binary...${NC}"
lipo -create -output "$OUTPUT_DIR/rg" "$ARM64_BIN" "$X86_64_BIN"

if [ ! -f "$OUTPUT_DIR/rg" ]; then
    echo -e "${RED}Failed to create universal binary${NC}"
    exit 1
fi

# Make executable
chmod +x "$OUTPUT_DIR/rg"

echo -e "${GREEN}Universal binary created${NC}"

echo -e "${YELLOW}[4/4] Verifying...${NC}"
echo ""

# Show architectures
echo -e "Architectures:"
lipo -info "$OUTPUT_DIR/rg"
echo ""

# Show version
echo -e "Version:"
"$OUTPUT_DIR/rg" --version | head -1
echo ""

# Show file size
SIZE=$(ls -lh "$OUTPUT_DIR/rg" | awk '{print $5}')
echo -e "File size: ${GREEN}$SIZE${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Download Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Binary location: ${GREEN}$OUTPUT_DIR/rg${NC}"
echo ""
