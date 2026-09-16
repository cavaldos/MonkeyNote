#!/bin/bash
# Mirror of .github/workflows/lint.yml + release.yml — run before push/tag.
# Usage: ./ci-local.sh [vX.Y.Z]  (pass tag to also validate tag format)
set -e
cd "$(dirname "$0")"

if ! command -v swiftlint >/dev/null; then
  echo "swiftlint not found — run: brew install swiftlint"
  exit 1
fi
echo "==> swiftlint --strict"
swiftlint --strict

echo "==> xcodebuild Release (same flags as release.yml)"
xcodebuild -project MonkeyNote.xcodeproj -scheme MonkeyNote -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  clean build >/dev/null
echo "build OK"

if [ -n "$1" ]; then
  if ! [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "tag '$1' must look like vX.Y.Z (e.g. v1.3.5)"
    exit 1
  fi
  echo "tag OK: $1"
fi

echo "ci-local PASS"
