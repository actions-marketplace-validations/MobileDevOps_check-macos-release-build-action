#!/usr/bin/env bash
#
# check-release-build.sh — verify a built macOS .app (or .dmg) is a proper
# RELEASE build: optimized, stripped, no dev-server references, sane bundle
# metadata, and no development entitlements.
#
# Runs standalone on a developer machine and as the engine of the
# check-release-build GitHub Action. When GITHUB_* env vars are present it
# additionally emits workflow annotations, step outputs and a job summary.
#
# Usage:
#   scripts/check-release-build.sh <path-to-.app | .dmg>
#   scripts/check-release-build.sh              # auto-detect under $SEARCH_PATH
#
# Configuration (all optional, mirrors the action inputs):
#   APP_PATH             explicit path to the .app or .dmg
#   SEARCH_PATH          root to auto-detect a bundle in (default: current directory)
#   REQUIRE_ARCH         arm64 | x86_64 | universal | any (default: arm64)
#   MAX_TEXT_SYMBOLS     symbol budget for a stripped binary (default: 5)
#   DEV_SERVER_PATTERN   extended regex that must NOT appear in the binary
#   REQUIRE_SIGNED       true -> unsigned is a failure instead of a warning
#   FAIL_ON_WARNINGS     true -> warnings are failures
#   EXPECTED_VERSION     assert CFBundleShortVersionString (leading "v" ignored)
#   EXPECTED_BUNDLE_ID   assert CFBundleIdentifier
#
# Exit status: 0 if it looks like a valid release build, 1 otherwise,
#              2 on usage/environment errors.

set -uo pipefail

# ---- output helpers --------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=; GREEN=; YELLOW=; BOLD=; RESET=
fi

PASS=0; FAIL=0; WARN=0
SUMMARY_ROWS=()
CURRENT_SECTION="General"
IN_ACTIONS="${GITHUB_ACTIONS:-false}"

# Escape a string for use inside a markdown table cell.
md_cell() { printf '%s' "${1//|/\\|}"; }

record() { # record <icon> <section> <message>
  SUMMARY_ROWS+=("| $1 | $(md_cell "$2") | $(md_cell "$3") |")
}

pass() { printf "  ${GREEN}✓${RESET} %s\n" "$1"; PASS=$((PASS+1)); record "✅" "$CURRENT_SECTION" "$1"; }

fail() {
  printf "  ${RED}✗${RESET} %s\n" "$1"; FAIL=$((FAIL+1)); record "❌" "$CURRENT_SECTION" "$1"
  [[ "$IN_ACTIONS" == "true" ]] && printf '::error title=Release build check::%s\n' "$1"
  return 0
}

warn() {
  printf "  ${YELLOW}!${RESET} %s\n" "$1"; WARN=$((WARN+1)); record "⚠️" "$CURRENT_SECTION" "$1"
  [[ "$IN_ACTIONS" == "true" ]] && printf '::warning title=Release build check::%s\n' "$1"
  return 0
}

sec() {
  CURRENT_SECTION="$1"
  printf "\n${BOLD}%s${RESET}\n" "$1"
  [[ "$IN_ACTIONS" == "true" ]] && printf '::group::%s\n' "$1"
  return 0
}

endsec() { [[ "$IN_ACTIONS" == "true" ]] && printf '::endgroup::\n'; return 0; }

die() { printf "${RED}Error:${RESET} %s\n" "$1" >&2; exit "${2:-2}"; }

set_output() { # set_output <name> <value>
  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
}

is_true() { [[ "${1:-}" =~ ^([Tt]rue|1|[Yy]es)$ ]]; }

# ---- configuration ---------------------------------------------------------
APP_PATH="${1:-${APP_PATH:-}}"
SEARCH_PATH="${SEARCH_PATH:-.}"
REQUIRE_ARCH="${REQUIRE_ARCH:-arm64}"
MAX_TEXT_SYMBOLS="${MAX_TEXT_SYMBOLS:-5}"
DEV_SERVER_PATTERN="${DEV_SERVER_PATTERN:-https?://(localhost|127\.0\.0\.1):(1420|3000|4200|5173|8080)}"
REQUIRE_SIGNED="${REQUIRE_SIGNED:-false}"
FAIL_ON_WARNINGS="${FAIL_ON_WARNINGS:-false}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-}"

[[ "$(uname)" == "Darwin" ]] || die "macOS only — run this on a macos-* runner."

case "$REQUIRE_ARCH" in
  arm64|x86_64|universal|any) ;;
  *) die "require-arch must be one of: arm64, x86_64, universal, any (got '$REQUIRE_ARCH')" ;;
esac

# ---- resolve the .app (mount a .dmg if needed) -----------------------------
DMG_MOUNT=""
cleanup() { [[ -n "$DMG_MOUNT" ]] && hdiutil detach "$DMG_MOUNT" -quiet 2>/dev/null || true; }
trap cleanup EXIT

if [[ -z "$APP_PATH" ]]; then
  # Auto-detect the most recently built bundle below $SEARCH_PATH.
  # -prune stops the descent at the first match, so helper .app bundles nested
  # inside the main bundle never shadow it.
  APP_PATH="$(find "$SEARCH_PATH" -maxdepth 6 \( -name '*.app' -o -name '*.dmg' \) -prune -print0 2>/dev/null \
              | xargs -0 ls -dt 2>/dev/null | head -1 || true)"
  [[ -n "$APP_PATH" ]] || die "no .app/.dmg found under '$SEARCH_PATH' — pass an explicit path."
  printf "${BOLD}Auto-detected:${RESET} %s\n" "$APP_PATH"
fi
[[ -e "$APP_PATH" ]] || die "not found: $APP_PATH"

if [[ "${APP_PATH##*.}" == "dmg" ]]; then
  DMG_MOUNT="$(hdiutil attach -nobrowse -readonly "$APP_PATH" | awk -F'\t' 'END{print $NF}')"
  [[ -n "$DMG_MOUNT" ]] || die "failed to mount dmg: $APP_PATH"
  APP="$(find "$DMG_MOUNT" -maxdepth 1 -name '*.app' | head -1)"
  [[ -n "$APP" ]] || die "no .app inside dmg: $APP_PATH"
else
  APP="$APP_PATH"
fi

printf "${BOLD}Checking release build:${RESET} %s\n" "$APP"

PLIST="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }

# ===========================================================================
sec "1. Bundle structure & metadata"
# ===========================================================================
if [[ -f "$PLIST" ]]; then pass "Info.plist present"; else fail "Info.plist missing"; fi

EXE_NAME="$(pb CFBundleExecutable)"
BIN="$APP/Contents/MacOS/$EXE_NAME"
if [[ -n "$EXE_NAME" && -x "$BIN" ]]; then
  pass "executable: Contents/MacOS/$EXE_NAME"
else
  fail "main executable missing or not executable"
fi

APP_VER="$(pb CFBundleShortVersionString)"
BUNDLE_ID="$(pb CFBundleIdentifier)"
MIN_OS="$(pb LSMinimumSystemVersion)"
BUNDLE_VER="$(pb CFBundleVersion)"

[[ -n "$BUNDLE_ID" ]] && pass "bundle id: $BUNDLE_ID" || fail "CFBundleIdentifier missing"
[[ -n "$APP_VER" ]]   && pass "version: $APP_VER"     || fail "CFBundleShortVersionString missing"
[[ -n "$MIN_OS" ]]    && pass "min macOS: $MIN_OS"    || warn "LSMinimumSystemVersion not set"

# Internal consistency of the artifact: the two Info.plist version fields
# should agree. (Do NOT compare against the local repo — a downloaded artifact
# is validated on its own, independent of whatever branch is checked out.)
if [[ -n "$APP_VER" && -n "$BUNDLE_VER" ]]; then
  if [[ "$APP_VER" == "$BUNDLE_VER" ]]; then
    pass "version fields consistent (short = bundle = $APP_VER)"
  else
    fail "version fields disagree: CFBundleShortVersionString=$APP_VER, CFBundleVersion=$BUNDLE_VER"
  fi
fi

if [[ -n "$EXPECTED_VERSION" ]]; then
  WANT_VER="${EXPECTED_VERSION#v}"
  if [[ "$APP_VER" == "$WANT_VER" ]]; then
    pass "version matches expected ($WANT_VER)"
  else
    fail "version mismatch: expected $WANT_VER, bundle says ${APP_VER:-<unset>}"
  fi
fi

if [[ -n "$EXPECTED_BUNDLE_ID" ]]; then
  if [[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]]; then
    pass "bundle id matches expected ($EXPECTED_BUNDLE_ID)"
  else
    fail "bundle id mismatch: expected $EXPECTED_BUNDLE_ID, bundle says ${BUNDLE_ID:-<unset>}"
  fi
fi
endsec

# ===========================================================================
sec "2. Architecture"
# ===========================================================================
ARCHS=""
if [[ -x "$BIN" ]]; then
  ARCHS="$(lipo -archs "$BIN" 2>/dev/null || echo "?")"
  case "$REQUIRE_ARCH" in
    any)
      pass "architectures: $ARCHS" ;;
    universal)
      if [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]; then
        pass "universal binary ($ARCHS)"
      else
        fail "not a universal binary ($ARCHS) — expected arm64 + x86_64"
      fi ;;
    *)
      if [[ "$ARCHS" == *"$REQUIRE_ARCH"* ]]; then
        pass "$REQUIRE_ARCH slice present ($ARCHS)"
      else
        fail "missing $REQUIRE_ARCH slice ($ARCHS)"
      fi ;;
  esac
fi
endsec

# ===========================================================================
sec "3. Release optimization (not a debug build)"
# ===========================================================================
if [[ -x "$BIN" ]]; then
  # Debug builds keep debug info. On macOS that is usually a debug *map* — OSO
  # stabs in the symbol table pointing at the .o files — rather than a __DWARF
  # section, so check for both. `strip -S` (what a release profile does)
  # removes them.
  DEBUG_HITS=()
  otool -l "$BIN" 2>/dev/null | grep -q "__DWARF" && DEBUG_HITS+=("__DWARF section")
  OSO_COUNT="$(nm -ap "$BIN" 2>/dev/null | grep -c ' OSO ' || true)"
  OSO_COUNT="${OSO_COUNT//[[:space:]]/}"
  [[ "${OSO_COUNT:-0}" -gt 0 ]] && DEBUG_HITS+=("$OSO_COUNT debug-map (OSO) entries")
  if [[ ${#DEBUG_HITS[@]} -gt 0 ]]; then
    fail "embedded debug info found (${DEBUG_HITS[*]}) — looks like a DEBUG build"
  else
    pass "no embedded debug info (stripped release binary)"
  fi

  # Stripped binaries expose few/no symbols (a couple may remain, e.g. entry).
  SYMS="$(nm "$BIN" 2>/dev/null | grep -c ' [tT] ' || true)"
  SYMS="${SYMS//[[:space:]]/}"
  if [[ "${SYMS:-0}" -le "$MAX_TEXT_SYMBOLS" ]]; then
    pass "symbol table stripped (${SYMS:-0} text symbols)"
  else
    warn "$SYMS text symbols present (release profile should strip symbols)"
  fi

  # A dev build loads its UI from a local dev server; a release build ships the
  # assets inside the bundle and must not reference one.
  if strings -a "$BIN" 2>/dev/null | grep -Eq "$DEV_SERVER_PATTERN"; then
    fail "dev-server URL matching /$DEV_SERVER_PATTERN/ embedded — this is a DEV build, not release"
  else
    pass "no dev-server URL embedded"
  fi
fi
endsec

# ===========================================================================
sec "4. Distribution entitlements (debug flag off)"
# ===========================================================================
if ! codesign -dv "$APP" >/dev/null 2>&1; then
  if is_true "$REQUIRE_SIGNED"; then
    fail "bundle is unsigned"
  else
    warn "unsigned — signing/notarization is checked separately"
  fi
else
  pass "bundle is code signed"
  ENT="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
  if grep -A1 "get-task-allow" <<<"$ENT" | grep -qi "<true/>"; then
    fail "com.apple.security.get-task-allow = true — this is a debug/development build"
  else
    pass "get-task-allow not enabled (distribution build)"
  fi
fi
endsec

# ===========================================================================
# Summary
# ===========================================================================
if is_true "$FAIL_ON_WARNINGS" && [[ $WARN -gt 0 ]]; then
  FAIL=$((FAIL+WARN)); WARN=0
fi

RESULT="pass"; [[ $FAIL -eq 0 ]] || RESULT="fail"

printf "\n${BOLD}Summary${RESET}\n"
printf "  %s%d passed%s, %s%d failed%s, %s%d warnings%s\n" \
  "$GREEN" "$PASS" "$RESET" "$RED" "$FAIL" "$RESET" "$YELLOW" "$WARN" "$RESET"

set_output "result" "$RESULT"
set_output "app-path" "$APP"
set_output "version" "$APP_VER"
set_output "bundle-id" "$BUNDLE_ID"
set_output "min-os" "$MIN_OS"
set_output "architectures" "$ARCHS"
set_output "passed" "$PASS"
set_output "failed" "$FAIL"
set_output "warnings" "$WARN"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    if [[ "$RESULT" == "pass" ]]; then
      printf '## ✅ Release build check passed\n\n'
    else
      printf '## ❌ Release build check failed\n\n'
    fi
    printf '**Bundle:** `%s`  \n' "$(basename "$APP")"
    printf '**Version:** %s · **Bundle ID:** `%s` · **Arch:** %s · **Min macOS:** %s\n\n' \
      "${APP_VER:-—}" "${BUNDLE_ID:-—}" "${ARCHS:-—}" "${MIN_OS:-—}"
    printf '%d passed · %d failed · %d warnings\n\n' "$PASS" "$FAIL" "$WARN"
    printf '| | Check | Detail |\n|---|---|---|\n'
    printf '%s\n' "${SUMMARY_ROWS[@]}"
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [[ "$RESULT" == "pass" ]]; then
  printf "\n${GREEN}${BOLD}OK — looks like a proper release build%s.${RESET}\n" "${APP_VER:+ (v$APP_VER)}"
  exit 0
else
  printf "\n${RED}${BOLD}NOT a clean release build — see failures above.${RESET}\n"
  exit 1
fi
