# Check macOS Release Build

[![Test action](https://github.com/MobileDevOps/check-macos-release-build-action/actions/workflows/test.yml/badge.svg)](https://github.com/MobileDevOps/check-macos-release-build-action/actions/workflows/test.yml)
[![GitHub Marketplace](https://img.shields.io/badge/marketplace-check--macos--release--build-purple?logo=github)](https://github.com/marketplace/actions/check-macos-release-build)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A GitHub Action that verifies a built macOS `.app` (or `.dmg`) really is a **release** build —
optimized, stripped, built for the right architecture, free of dev-server references, and without
development entitlements — before you ship it.

It answers the question CI usually skips: *the build succeeded, but is this the artifact we meant to
release?* Signing and notarization are a separate concern; this action checks the build itself.

## What it checks

| # | Group | Checks |
|---|---|---|
| 1 | Bundle structure & metadata | `Info.plist` present, main executable present and executable, `CFBundleIdentifier` / `CFBundleShortVersionString` / `LSMinimumSystemVersion` set, `CFBundleShortVersionString` and `CFBundleVersion` agree, optional expected version and bundle id |
| 2 | Architecture | required slice present (`arm64`, `x86_64`, `universal`, or `any`) |
| 3 | Release optimization | no embedded debug info (`__DWARF` section or OSO debug-map stabs), symbol table stripped, no dev-server URL embedded |
| 4 | Distribution entitlements | bundle is signed, `com.apple.security.get-task-allow` is not enabled |

Version fields are validated *within the artifact*, never against the checked-out repo — a downloaded
artifact is judged on its own.

Results appear as workflow annotations and as a job summary table.

> **Requires a macOS runner** (`runs-on: macos-latest`). The checks use `lipo`, `otool`, `nm`,
> `strings`, `codesign` and `PlistBuddy`.

## Usage

```yaml
jobs:
  verify:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      # ... build your app ...

      - uses: MobileDevOps/check-macos-release-build-action@v1
        with:
          path: build/Release/MyApp.app
```

### Auto-detection

Omit `path` and the most recently built `.app` or `.dmg` below `search-path` is used. Point it at
your build output directory — searching from the repo root works, but is slower and can pick the
wrong bundle if several exist:

```yaml
      - uses: MobileDevOps/check-macos-release-build-action@v1
        with:
          search-path: build/Release
```

### Gate a release on the tag version

```yaml
      - uses: MobileDevOps/check-macos-release-build-action@v1
        with:
          path: dist/MyApp.dmg
          expected-version: ${{ github.ref_name }}   # leading "v" is stripped
          expected-bundle-id: com.example.myapp
          require-signed: true
```

### Report without failing the job

```yaml
      - id: check
        uses: MobileDevOps/check-macos-release-build-action@v1
        with:
          path: dist/MyApp.app
          fail-on-error: false

      - if: steps.check.outputs.result == 'fail'
        run: echo "Shipping anyway, but ${{ steps.check.outputs.failed }} checks failed."
```

### Universal binaries

```yaml
      - uses: MobileDevOps/check-macos-release-build-action@v1
        with:
          path: dist/MyApp.app
          require-arch: universal
```

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `path` | *(empty)* | Path to the `.app` or `.dmg`. Empty → auto-detect below `search-path`. |
| `search-path` | `.` | Root directory for auto-detection. |
| `require-arch` | `arm64` | Required architecture: `arm64`, `x86_64`, `universal`, or `any`. |
| `max-text-symbols` | `5` | Text-symbol budget before the binary is flagged as unstripped. |
| `dev-server-pattern` | `https?://(localhost\|127\.0\.0\.1):(1420\|3000\|4200\|5173\|8080)` | Extended regex that must **not** appear in the binary. Defaults to a localhost URL on a common dev-server port. |
| `require-signed` | `false` | Fail (instead of warn) when the bundle is unsigned. |
| `expected-version` | *(empty)* | Assert `CFBundleShortVersionString`. A leading `v` is stripped. |
| `expected-bundle-id` | *(empty)* | Assert `CFBundleIdentifier`. |
| `fail-on-warnings` | `false` | Treat warnings as failures. |
| `fail-on-error` | `true` | Fail the step when the check does not pass. |

## Outputs

| Name | Description |
|------|-------------|
| `result` | `pass` or `fail` |
| `app-path` | Path of the `.app` that was checked (the mounted bundle when the input was a `.dmg`) |
| `version` | `CFBundleShortVersionString` |
| `bundle-id` | `CFBundleIdentifier` |
| `min-os` | `LSMinimumSystemVersion` |
| `architectures` | Architecture slices found in the main binary |
| `passed` / `failed` / `warnings` | Check counts |

## Adapting to your toolchain

The checks are toolchain-agnostic — anything producing a macOS `.app` works (Xcode, Rust, Electron,
Qt, Go, a hand-rolled bundler). Two inputs are worth tuning:

- `search-path` — your build output directory, so auto-detection stays fast and unambiguous.
- `dev-server-pattern` — the URL your *dev* build embeds but your release build must not. The
  default covers common dev-server ports; override it if yours differs.

```yaml
        with:
          search-path: build/Release
          dev-server-pattern: 'https?://(localhost|127\.0\.0\.1):9000'
```

If your app legitimately embeds a localhost URL in release builds — an OAuth loopback redirect, for
example — narrow the pattern so it does not match that URL.

## Running locally

The action is a thin wrapper around a standalone script:

```bash
scripts/check-release-build.sh path/to/MyApp.app
REQUIRE_ARCH=universal EXPECTED_VERSION=1.4.0 scripts/check-release-build.sh dist/MyApp.dmg
```

Every input has an environment-variable equivalent — see the header of the script.

## Development

```bash
mkdir -p build
test/make-fixture.sh release build     # also: debug, dev
scripts/check-release-build.sh build/Fixture.app
```

`test/make-fixture.sh` builds a minimal `.app` in a known-good or known-bad shape; the workflow in
`.github/workflows/test.yml` runs the action against all three and asserts the expected verdict.

## Contributing

Bug reports, new checks, and toolchain notes are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md)
for the development setup and what makes a good check. Participation is covered by our
[Code of Conduct](CODE_OF_CONDUCT.md).

## Support

Questions and "why does my build fail this check?" belong in
[Discussions](https://github.com/MobileDevOps/check-macos-release-build-action/discussions) —
see [SUPPORT.md](SUPPORT.md).

## Security

Report vulnerabilities privately — see [SECURITY.md](SECURITY.md). Never open a public issue for
a security problem.

## Changelog

Notable changes are listed in [CHANGELOG.md](CHANGELOG.md). Pin the action by major tag (`@v1`)
to pick up fixes automatically, or by commit SHA for an immutable reference.

## License

MIT — see [LICENSE](LICENSE).
