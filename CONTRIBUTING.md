# Contributing to Check macOS Release Build

Thanks for wanting to improve this action.

## Development setup

Requires macOS — the checks use `lipo`, `otool`, `nm`, `strings`, `codesign` and `PlistBuddy`.

```bash
git clone https://github.com/MobileDevOps/check-macos-release-build-action.git
cd check-macos-release-build-action

# Build a fixture bundle and run the script against it
mkdir -p build
test/make-fixture.sh release build     # also: debug, dev
scripts/check-release-build.sh build/Fixture.app
```

`test/make-fixture.sh <kind> <dir>` produces a minimal `.app` in a known-good (`release`) or
known-bad (`debug`, `dev`) shape. The `release` fixture must pass; the other two must fail.

Run the linter the CI runs:

```bash
shellcheck -S warning scripts/check-release-build.sh test/make-fixture.sh
```

## How to contribute

### Reporting bugs

Search [existing issues](https://github.com/MobileDevOps/check-macos-release-build-action/issues) first.
Include the failing check line, your workflow step, and how the bundle was built —
see [SUPPORT.md](SUPPORT.md).

### Suggesting a new check

Open a discussion or an issue with the `enhancement` label. A good check is:

- **Toolchain-agnostic** — true for any macOS `.app`, not just one bundler
- **Low false-positive** — a legitimate release build must never trip it
- **Cheap** — no network, no notarization round-trip

Anything about signing or notarization is deliberately out of scope: this action judges the build,
not its distribution credentials.

### Pull requests

1. Branch from `main`: `git checkout -b feat/my-change`
2. Add or adjust a fixture in `test/make-fixture.sh` if the change affects verdicts
3. Keep `shellcheck -S warning` clean
4. Update `README.md` when inputs or outputs change — and `action.yml` descriptions with it
5. Add an entry to `CHANGELOG.md` under `[Unreleased]`
6. Open the PR against `main` with a descriptive title

## Conventions

### Shell

- `bash`, `set -euo pipefail`, `shellcheck` clean at `-S warning`
- Every input has an environment-variable equivalent documented in the script header
- Use `pass` / `fail` / `warn` so results land in the annotations *and* the job summary
- Never `exit` from inside a check — accumulate into `FAIL`/`WARN` so a run reports everything

### Action inputs

- kebab-case names, mirrored to `SCREAMING_SNAKE_CASE` env vars in `action.yml`
- Every new input needs: a default, an `action.yml` description, a README table row, and a
  script-header line

### Commits

Use [Conventional Commits](https://www.conventionalcommits.org):
`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `test:`, `refactor:`.

## Releases

Maintainers only. Tag `vX.Y.Z`, publish the GitHub release, and the
[`release`](.github/workflows/release.yml) workflow moves the floating `vX` tag so
`@v1` consumers pick the change up.
