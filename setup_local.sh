#!/bin/bash
# Copies sensitive config files from ~/.tinkerplex/ into the project.
# Run once after cloning, or after clearing build artifacts.

set -e

CONFIG_DIR="$HOME/.tinkerplex"

if [ ! -d "$CONFIG_DIR" ]; then
  echo "ERROR: $CONFIG_DIR does not exist."
  echo "Create it and add: google-services-issueinator.json"
  exit 1
fi

# google-services.json
SRC="$CONFIG_DIR/google-services-issueinator.json"
DEST="android/app/google-services.json"
if [ -f "$SRC" ]; then
  cp "$SRC" "$DEST"
  echo "Copied google-services.json"
else
  echo "WARNING: $SRC not found — Google Sign-In will not work"
fi

echo "Local setup complete."
