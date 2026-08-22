#!/usr/bin/env bash
#
# make-fixture.sh — build a minimal macOS .app used to exercise
# scripts/check-release-build.sh in CI and locally.
#
# Usage: test/make-fixture.sh <release|debug|dev> <output-dir>
#
#   release  stripped, optimized, no dev-server URL   -> expected to pass
#   debug    -g with DWARF and unstripped symbols     -> expected to fail
#   dev      stripped but embeds the dev-server URL   -> expected to fail

set -euo pipefail

KIND="${1:?usage: make-fixture.sh <release|debug|dev> <output-dir>}"
OUT="${2:?usage: make-fixture.sh <release|debug|dev> <output-dir>}"

APP="$OUT/Fixture.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

SRC="$(mktemp -t fixture).c"
case "$KIND" in
  dev) URL_LINE='const char *dev_url = "http://localhost:5173";' ;;
  *)   URL_LINE='const char *dev_url = "app://localhost";' ;;
esac
cat >"$SRC" <<EOF
#include <stdio.h>
$URL_LINE
static int helper_one(int a) { return a * 3; }
static int helper_two(int a) { return helper_one(a) + 7; }
int main(void) { printf("%s %d\n", dev_url, helper_two(2)); return 0; }
EOF

BIN="$APP/Contents/MacOS/Fixture"
case "$KIND" in
  debug) clang -g -O0 -arch arm64 -o "$BIN" "$SRC" ;;
  *)     clang -O2 -arch arm64 -o "$BIN" "$SRC"; strip -x -S "$BIN" ;;
esac
rm -f "$SRC"

cat >"$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Fixture</string>
  <key>CFBundleIdentifier</key><string>com.mobiledevops.fixture</string>
  <key>CFBundleName</key><string>Fixture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.3</string>
  <key>CFBundleVersion</key><string>1.2.3</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
EOF

echo "$APP"
