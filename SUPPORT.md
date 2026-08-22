# Support

## Documentation

- [README](README.md) — inputs, outputs, usage examples, and how to adapt the checks to your toolchain
- [`scripts/check-release-build.sh`](scripts/check-release-build.sh) — the standalone script the action wraps; its header documents every environment variable

## Getting help

1. Read the README — most questions are about `search-path` auto-detection or the
   `dev-server-pattern` default.
2. Search [existing issues](https://github.com/mobiledevops/check-release-build-action/issues).
3. Ask in [Discussions](https://github.com/mobiledevops/check-release-build-action/discussions) —
   best for "why does my build fail this check?" questions.
4. For a confirmed bug, open an issue with the
   [bug report template](https://github.com/mobiledevops/check-release-build-action/issues/new?template=bug_report.yml).

## What to include when asking

The action prints a full check list and writes a job summary table. Include:

- The failing check line (or the whole step log)
- The `with:` block of your workflow step
- Your build toolchain (Xcode, Tauri, Electron, Go, …) and how the bundle is produced

## Reporting security issues

Do not use issues or discussions — see [SECURITY.md](SECURITY.md).
