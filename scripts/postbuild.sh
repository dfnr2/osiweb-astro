#!/bin/bash
set -e

DIST="dist"
FORUM="$DIST/forum"
OSIFORUM="$DIST/osiforum"

# Remove old symlink if it exists
if [ -L "$OSIFORUM" ]; then
  rm "$OSIFORUM"
fi

# Create symlink
ln -s forum "$OSIFORUM"
echo "Symlink created: osiforum -> forum"
