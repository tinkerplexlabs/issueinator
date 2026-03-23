#!/bin/bash
# Build a signed AAB for local upload to Play Console
#
# Usage:
#   ./build_aab.sh           # uses version from pubspec.yaml
#   ./build_aab.sh 0.1.0     # sets version to 0.1.0
#   ./build_aab.sh 1.2.3     # sets version to 1.2.3

set -e

# Ensure google-services.json is in place
if [ ! -f "android/app/google-services.json" ]; then
  if [ -f "setup_local.sh" ]; then
    echo "google-services.json missing — running setup_local.sh..."
    ./setup_local.sh
  else
    echo "ERROR: android/app/google-services.json not found"
    exit 1
  fi
fi

VERSION="${1:-}"

# Generate timestamp-based version code (same algorithm as CI)
CURRENT_YEAR=$(date -u +"%Y")
YEAR_OFFSET=$((CURRENT_YEAR - 2025))
TIMESTAMP_VERSION_CODE=$(printf "%02d%s" $YEAR_OFFSET "$(date -u +"%m%d%H%M")")
VERSION_CODE=$((10#$TIMESTAMP_VERSION_CODE))

if [ -n "$VERSION" ]; then
  echo "Setting version to $VERSION+$VERSION_CODE"
  sed -i "s/^version:.*/version: $VERSION+$VERSION_CODE/" pubspec.yaml
else
  VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)
  sed -i "s/^version:.*/version: $VERSION+$VERSION_CODE/" pubspec.yaml
  echo "Using version $VERSION+$VERSION_CODE"
fi

echo "Building release AAB..."
flutter build appbundle --release

AAB="build/app/outputs/bundle/release/app-release.aab"
if [ -f "$AAB" ]; then
  SIZE=$(du -h "$AAB" | cut -f1)
  echo ""
  echo "Build successful: $AAB ($SIZE)"
  echo "Version: $VERSION+$VERSION_CODE"
else
  echo "ERROR: AAB not found"
  exit 1
fi
