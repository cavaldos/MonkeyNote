#!/bin/bash
set -e
xcodebuild -project MonkeyNote.xcodeproj -scheme MonkeyNote -configuration Debug -destination "platform=macOS,arch=arm64" build
APP_DIR=$(xcodebuild -project MonkeyNote.xcodeproj -scheme MonkeyNote -configuration Debug -destination "platform=macOS,arch=arm64" -showBuildSettings 2>/dev/null | grep -m 1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')
pkill -x MonkeyNote 2>/dev/null || true
open "$APP_DIR/MonkeyNote.app"
