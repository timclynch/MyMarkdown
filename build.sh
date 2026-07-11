#!/bin/zsh
# Builds MarkPad.app from the Swift sources in ./Sources
# Assembles in a temp dir (outside iCloud sync) so codesign isn't
# disturbed by Finder/file-provider metadata, then copies back here.
set -e
cd "$(dirname "$0")"

APP="MarkPad.app"
ARCH="$(uname -m)"

# Generate the app icon once
if [[ ! -f AppIcon.icns ]]; then
  echo "Generating icon…"
  swift make-icon.swift
  iconutil -c icns AppIcon.iconset -o AppIcon.icns
  rm -rf AppIcon.iconset
fi

BUILD_DIR="$(mktemp -d /tmp/markpad-build.XXXXXX)"
STAGED="$BUILD_DIR/$APP"

echo "Compiling…"
mkdir -p "$STAGED/Contents/MacOS" "$STAGED/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library \
  -target "${ARCH}-apple-macos14.0" \
  Sources/*.swift \
  -framework AppKit -framework WebKit \
  -o "$STAGED/Contents/MacOS/MarkPad"

cat Info.plist > "$STAGED/Contents/Info.plist"
cat AppIcon.icns > "$STAGED/Contents/Resources/AppIcon.icns"

xattr -cr "$STAGED"
codesign --force -s - "$STAGED"
codesign -v "$STAGED"

rm -rf "$APP"
ditto "$STAGED" "$APP"
rm -rf "$BUILD_DIR"
echo "Built $APP"
