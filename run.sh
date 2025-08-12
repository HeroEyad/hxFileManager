#!/bin/bash
set -e

ZIP_NAME="hxFileManager.zip"
BIN_FOLDER="bin"

if [ -f "$ZIP_NAME" ]; then
    rm "$ZIP_NAME"
fi

if [ -d "$BIN_FOLDER" ]; then
    echo "Removing existing $BIN_FOLDER folder..."
    rm -rf "$BIN_FOLDER"
fi

echo "Creating ZIP for hxFileManager: $ZIP_NAME"
zip -r "$ZIP_NAME" . -x "*.git*" -x "*.sh" -x "*.bat"

echo "Installing to haxelib..."
haxelib install "$ZIP_NAME" --skip-dependencies

# Remove ZIP 

echo "Done!"
