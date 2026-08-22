# Copilot Instructions

## Project overview

A GitHub composite action that verifies a built macOS `.app` or `.dmg` is a genuine **release**
build — optimized, stripped, correct architecture, no dev-server URLs, no debug entitlements,
consistent bundle metadata. Signing and notarization are explicitly out of scope.

## Tech stack

- Bash 3.2+ (the macOS system bash), `set -euo pipefail`
- macOS toolchain: `lipo`, `otool`, `nm`, `strings`, `codesign`, `/usr/libexec/PlistBuddy`,
  `hdiutil` (for `.dmg`)
- GitHub Actions composite action (`action.yml`) — no Node, no bundled dependencies
- Runs only on `macos-*` runners; `action.yml` guards this with a `uname` check

## Layout

- `action.yml` — inputs/outputs; maps kebab-case inputs to `SCREAMING_SNAKE_CASE` env vars, runs
  the script with `continue-on-error`, then a separate step decides the job verdict from
  `fail-on-error`
- `scripts/check-release-build.sh` — all check logic; runs standalone on a dev machine and as the
  action's engine. Emits annotations, `GITHUB_OUTPUT` values, and a `GITHUB_STEP_SUMMARY` table
  only when the corresponding `GITHUB_*` vars are set
- `test/make-fixture.sh <release|debug|dev> <dir>` — builds a minimal `.app` in a known-good or
  known-bad shape
- `.github/workflows/test.yml` — runs the action against all three fixtures and asserts verdicts

## Conventions

- Every action input has an environment-variable equivalent, documented in the script header
- Checks report through `pass` / `fail` / `warn`, which increment counters *and* append a summary
  row — never `echo` a verdict directly, and never `exit` from inside a check; a run reports
  everything it found
- Sections are opened with `sec "Name"` and closed with `endsec` (these emit `::group::`)
- `is_true` accepts `true|1|yes` case-insensitively — use it for boolean inputs
- `die <msg>` for usage/environment errors (exit 2); check failures use exit 1
- Keep `shellcheck -S warning` clean
- Adding an input requires: `action.yml` entry + env mapping, a default in the script, a script
  header line, and a README table row

## Testing

```bash
mkdir -p build && test/make-fixture.sh release build
scripts/check-release-build.sh build/Fixture.app
shellcheck -S warning scripts/check-release-build.sh test/make-fixture.sh
```

The `release` fixture must pass; `debug` and `dev` must fail.

## Non-obvious context

- Debug info on macOS is usually an OSO debug *map* in the symbol table, not a `__DWARF` section —
  both are checked
- Auto-detection uses `-prune` so helper `.app` bundles nested inside the main bundle cannot
  shadow it
- `expected-version` strips a leading `v`, so a tag name like `v1.4.0` works directly
- Version fields are validated within the artifact, never against the checked-out repo
