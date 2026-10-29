#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/MacPerf.app"
BUILD="$ROOT/build"

rm -rf "$APP" "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD"

echo "==> Compiling SMC bridge"
clang -O2 -mmacosx-version-min=14.0 -c "$ROOT/Sources/SMCBridge.c" -o "$BUILD/SMCBridge.o"

echo "==> Compiling Swift app"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"

swiftc -O -swift-version 5 \
  -target "$TARGET" \
  -import-objc-header "$ROOT/Sources/Bridge.h" \
  "$ROOT"/Sources/*.swift \
  "$BUILD/SMCBridge.o" \
  -o "$APP/Contents/MacOS/MacPerf" \
  -framework SwiftUI \
  -framework AppKit \
  -framework IOKit \
  -framework CoreGraphics \
  -framework ColorSync

echo "==> Assembling bundle"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null

echo "==> Built $APP"
