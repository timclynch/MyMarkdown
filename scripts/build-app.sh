#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="MyMarkdown"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

cd "$ROOT"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILD_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  swift "$ROOT/scripts/make-icon.swift" "$ROOT/Resources"
fi
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

xattr -cr "$APP_DIR"
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"

rm -f "$ROOT/dist/$APP_NAME.zip"
(
  cd "$ROOT/dist"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry "$APP_NAME.zip" "$APP_NAME.app"
)
echo "$APP_DIR"
