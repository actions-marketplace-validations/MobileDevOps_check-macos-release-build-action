# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Composite action verifying a macOS `.app` or `.dmg` is a real release build.
- Bundle structure and metadata checks — `Info.plist`, main executable, `CFBundleIdentifier`,
  `CFBundleShortVersionString` / `CFBundleVersion` agreement, `LSMinimumSystemVersion`, plus
  optional `expected-version` and `expected-bundle-id` assertions.
- Architecture check with `require-arch`: `arm64`, `x86_64`, `universal`, or `any`.
- Release-optimization checks: no `__DWARF` section or OSO debug-map stabs, symbol table stripped
  within `max-text-symbols`, no URL matching `dev-server-pattern` embedded in the binary.
- Distribution-entitlement checks: bundle is signed (`require-signed`), and
  `com.apple.security.get-task-allow` is not enabled.
- `.dmg` support — mounts read-only and checks the `.app` inside.
- Auto-detection of the most recently built bundle below `search-path`.
- Workflow annotations, step outputs, and a job summary table.
- `fail-on-warnings` and `fail-on-error` to control how results gate the job.
- Fixture-based CI (`release` / `debug` / `dev`) plus `shellcheck`.
- Community health files, issue/PR/discussion templates, `CODEOWNERS`, Dependabot config, and a
  release workflow that moves the floating major tag.

[Unreleased]: https://github.com/mobiledevops/check-release-build-action/commits/main
