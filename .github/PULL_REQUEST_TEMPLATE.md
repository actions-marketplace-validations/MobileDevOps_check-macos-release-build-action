## Description

<!-- What does this PR change, and why? Link the issue it closes. -->

Closes #

## Type of change

- [ ] Bug fix
- [ ] New or changed check
- [ ] New or changed input/output
- [ ] Breaking change
- [ ] Documentation
- [ ] CI / maintenance

## Testing

- [ ] `shellcheck -S warning scripts/check-release-build.sh test/make-fixture.sh` is clean
- [ ] Ran against the `release` fixture — still passes
- [ ] Ran against the `debug` and `dev` fixtures — still fail
- [ ] Tested against a real app bundle (state the toolchain: )

## Checklist

- [ ] `README.md` updated if inputs, outputs, or behavior changed
- [ ] `action.yml` input/output descriptions match the README
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] No new false positives for a legitimate release build
- [ ] Conventional commit messages used
