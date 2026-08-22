#!/usr/bin/env bash
#
# check-release-build.sh — verify a built Tauri macOS app is a proper RELEASE
# build (optimized, not a debug/dev build), with sane bundle metadata.
#
# Complements check-notarization.sh (which checks signing/notarization).
#
# Usage:
#   scripts/check-release-build.sh <path-to-.app | .dmg>
#   scripts/check-release-build.sh            # auto-detect the built app in src-tauri/target
#
# Exit status: 0 if it looks like a valid release build, 1 otherwise.

set -uo pipefail

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=; GREEN=; YELLOW=; BOLD=; RESET=
fi
PASS=0; FAIL=0; WARN=0
pass() { printf "  ${GREEN}✓${RESET} %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗${RESET} %s\n" "$1"; FAIL=$((FAIL+1)); }
warn() { printf "  ${YELLOW}!${RESET} %s\n" "$1"; WARN=$((WARN+1)); }
sec() { printf "\n${BOLD}%s${RESET}\n" "$1"; }

[[ "$(uname)" == "Darwin" ]] || { echo "${RED}Error:${RESET} macOS only." >&2; exit 2; }

# ---- resolve the .app (mount a .dmg if needed) ----------------------------
DMG_MOUNT=""
cleanup() { [[ -n "$DMG_MOUNT" ]] && hdiutil detach "$DMG_MOUNT" -quiet 2>/dev/null || true; }
trap cleanup EXIT

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  # Auto-detect the most recent release bundle in the repo.
  TARGET="$(ls -dt src-tauri/target/*/release/bundle/macos/*.app \
                    src-tauri/target/release/bundle/macos/*.app 2>/dev/null | head -1 || true)"
  [[ -n "$TARGET" ]] || { echo "${RED}Error:${RESET} no built .app found under src-tauri/target — pass a path." >&2; exit 2; }
  echo "${BOLD}Auto-detected:${RESET} $TARGET"
fi
[[ -e "$TARGET" ]] || { echo "${RED}Error:${RESET} not found: $TARGET" >&2; exit 2; }

if [[ "${TARGET##*.}" == "dmg" ]]; then
  DMG_MOUNT="$(hdiutil attach -nobrowse -readonly "$TARGET" | awk -F'\t' 'END{print $NF}')"
  APP="$(find "$DMG_MOUNT" -maxdepth 1 -name '*.app' | head -1)"
  [[ -n "$APP" ]] || { echo "${RED}Error:${RESET} no .app inside dmg." >&2; exit 2; }
else
  APP="$TARGET"
fi

printf "${BOLD}Checking release build:${RESET} %s\n" "$APP"

# ---- locate the main executable -------------------------------------------
PLIST="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }

# ===========================================================================
sec "1. Bundle structure & metadata"
# ===========================================================================
if [[ -f "$PLIST" ]]; then pass "Info.plist present"; else fail "Info.plist missing"; fi
EXE_NAME="$(pb CFBundleExecutable)"
BIN="$APP/Contents/MacOS/$EXE_NAME"
if [[ -x "$BIN" ]]; then pass "executable: Contents/MacOS/$EXE_NAME"; else fail "main executable missing/not executable"; fi

APP_VER="$(pb CFBundleShortVersionString)"
BUNDLE_ID="$(pb CFBundleIdentifier)"
MIN_OS="$(pb LSMinimumSystemVersion)"
[[ -n "$BUNDLE_ID" ]] && pass "bundle id: $BUNDLE_ID" || fail "CFBundleIdentifier missing"
[[ -n "$APP_VER" ]]   && pass "version: $APP_VER"     || fail "CFBundleShortVersionString missing"
[[ -n "$MIN_OS" ]]    && pass "min macOS: $MIN_OS"     || warn "LSMinimumSystemVersion not set"

# Internal consistency of the artifact: the two Info.plist version fields
# should agree. (Do NOT compare against the local repo — a downloaded artifact
# is validated on its own, independent of whatever branch is checked out.)
BUNDLE_VER="$(pb CFBundleVersion)"
if [[ -n "$APP_VER" && -n "$BUNDLE_VER" ]]; then
  if [[ "$APP_VER" == "$BUNDLE_VER" ]]; then
    pass "version fields consistent (short = bundle = $APP_VER)"
  else
    fail "version fields disagree: CFBundleShortVersionString=$APP_VER, CFBundleVersion=$BUNDLE_VER"
  fi
fi

# ===========================================================================
sec "2. Architecture"
# ===========================================================================
if [[ -x "$BIN" ]]; then
  ARCHS="$(lipo -archs "$BIN" 2>/dev/null || echo "?")"
  if [[ "$ARCHS" == *arm64* ]]; then
    pass "arm64 (Apple Silicon) binary ($ARCHS)"
  else
    fail "missing arm64 slice ($ARCHS) — expected an Apple Silicon build"
  fi
fi

# ===========================================================================
sec "3. Release optimization (not a debug build)"
# ===========================================================================
if [[ -x "$BIN" ]]; then
  # Debug builds embed DWARF debug info; release (with strip) does not.
  if otool -l "$BIN" 2>/dev/null | grep -q "__DWARF"; then
    fail "embedded DWARF debug info found — looks like a DEBUG build"
  else
    pass "no embedded debug info (stripped release binary)"
  fi

  # Stripped binaries expose few/no symbols (a couple may remain, e.g. entry).
  SYMS="$(nm "$BIN" 2>/dev/null | grep -c ' [tT] ' || true)"
  if [[ "${SYMS:-0}" -le 5 ]]; then
    pass "symbol table stripped (${SYMS:-0} text symbols)"
  else
    warn "$SYMS text symbols present (release profile should strip symbols)"
  fi

  # The Tauri dev build points the webview at the Vite dev server; a release
  # build embeds the frontend and must not reference it.
  if strings -a "$BIN" 2>/dev/null | grep -Eq 'https?://(localhost|127\.0\.0\.1):1420'; then
    fail "dev-server URL (…:1420) embedded — this is a DEV build, not release"
  else
    pass "no dev-server URL embedded"
  fi
fi

# ===========================================================================
sec "4. Distribution entitlements (debug flag off)"
# ===========================================================================
if ! codesign -dv "$APP" >/dev/null 2>&1; then
  warn "unsigned — run check-notarization.sh once it is signed"
else
  ENT="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
  if grep -A1 "get-task-allow" <<<"$ENT" | grep -qi "<true/>"; then
    fail "com.apple.security.get-task-allow = true — this is a debug/development build"
  else
    pass "get-task-allow not enabled (distribution build)"
  fi
fi

# ===========================================================================
sec "Summary"
printf "  %s%d passed%s, %s%d failed%s, %s%d warnings%s\n" \
  "$GREEN" "$PASS" "$RESET" "$RED" "$FAIL" "$RESET" "$YELLOW" "$WARN" "$RESET"
if [[ $FAIL -eq 0 ]]; then
  printf "\n${GREEN}${BOLD}OK — looks like a proper release build%s.${RESET}\n" \
    "${APP_VER:+ (v$APP_VER)}"
  exit 0
else
  printf "\n${RED}${BOLD}NOT a clean release build — see failures above.${RESET}\n"
  exit 1
fi
