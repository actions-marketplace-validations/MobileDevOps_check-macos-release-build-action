# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| `v1.x`  | ✅ |
| `< v1`  | ❌ |

Pin the action by major tag (`@v1`) to receive fixes, or by commit SHA if your threat model
requires immutable references.

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately via
[GitHub Private Vulnerability Reporting](https://github.com/mobiledevops/check-release-build-action/security/advisories/new),
or by email to <sebastian@messeb.com>.

Please include:

- A description of the vulnerability and its impact
- Steps to reproduce (a minimal workflow is ideal)
- The action version or commit SHA affected
- Any suggested fix

We aim to acknowledge reports within 48 hours and to ship a patch for confirmed critical issues
within 14 days.

## Threat model notes

This action runs as a **composite action** — its shell steps execute in your workflow's runner
context with whatever permissions that job has. Relevant considerations:

- The action requires no secrets and makes no network requests.
- It reads the bundle you point it at and runs macOS toolchain binaries (`lipo`, `otool`, `nm`,
  `strings`, `codesign`, `PlistBuddy`) against it.
- `dev-server-pattern` is passed to `grep -E`. Treat it as trusted configuration — do not build it
  from untrusted input such as a PR title or issue body.
- Mounting an untrusted `.dmg` (`hdiutil attach`) exposes the runner to the disk image's contents.
  Only check artifacts your own pipeline produced.

## Security best practices for consumers

- Pin third-party actions by SHA in workflows triggered by `pull_request_target`.
- Grant the smallest `permissions:` block that the job needs.
- Never pass secrets into this action's inputs — it needs none.
