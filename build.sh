#!/bin/zsh
# Builds MarkPad.app from the Swift sources in ./Sources
# Assembles in a temp dir (outside iCloud sync) so codesign isn't
# disturbed by Finder/file-provider metadata, then copies back here.
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"

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

cp Info.plist "$STAGED/Contents/Info.plist"
cp AppIcon.icns "$STAGED/Contents/Resources/AppIcon.icns"

xattr -cr "$STAGED"
codesign --force -s - "$STAGED"
codesign -v "$STAGED"

rm -rf "$APP" MarkPad.zip
(
  cd "$BUILD_DIR"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry "$ROOT/MarkPad.zip" "$APP"
)
ditto "$STAGED" "$APP"
rm -rf "$BUILD_DIR"
echo "Built $APP and MarkPad.zip"
