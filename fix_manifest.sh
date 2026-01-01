#!/bin/bash

# Find the image_gallery_saver plugin directory in pub cache
PLUGIN_DIR=$(find ~/.pub-cache/git -name "image_gallery_saver-*" -type d 2>/dev/null | head -n 1)

if [ -z "$PLUGIN_DIR" ]; then
    echo "Error: image_gallery_saver plugin directory not found in pub cache"
    exit 1
fi

MANIFEST_FILE="$PLUGIN_DIR/android/src/main/AndroidManifest.xml"

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Error: AndroidManifest.xml not found at $MANIFEST_FILE"
    exit 1
fi

echo "Found manifest at: $MANIFEST_FILE"

# Remove the package attribute from the manifest tag
sed -i.bak 's/package="com\.example\.imagegallerysaver"//g' "$MANIFEST_FILE"

echo "✓ Successfully removed package attribute from AndroidManifest.xml"
echo "Backup created at: $MANIFEST_FILE.bak"
