# TODO

Use this file to track work that needs to be done. Lint scripts automatically append baseline-cleanup entries here when all violations for a linter reach zero.

# Task: Run builds after an all-versions dispatch

## Steps
- [x] Update the `build` and `merge` job conditions in `.github/workflows/docker-build.yml`.
- [x] Run relevant workflow validation and review the final diff.

## Definition of Done
- The downstream jobs can run when `prepare` is intentionally skipped, but only if `detect` succeeded, versions were detected, and the run was not cancelled.
- Existing validation passes and the changed files contain no secrets.

- [ ] Remove shellcheck baseline comparison: delete tests/baselines/shellcheck-baseline.json and the baseline comparison logic from tests/lint-shell.sh, and update the script to fail when shellcheck reports any violations (fail when the generated JSON is non-empty). After that, any new shellcheck violation will be an immediate CI failure.

# Task: Use archived Bullseye package sources

## Steps
- [x] Identify that PHP 7.4's Bullseye security repository returns 404 for the `unzip` package after Bullseye LTS ended.
- [x] Configure Bullseye stages to use Debian's archive repository and accept its expired metadata.
- [x] Run focused Dockerfile lint/configuration validation and review the final diff.
- [x] Scan changed files for secrets.
- [ ] Run parallel code validation.

## Definition of Done
- Bullseye downloader and extension stages inherit Debian Archive sources with expired metadata checks disabled.
- Focused validation passes, the diff stays limited to the fix and this checklist, and changed files contain no secrets.
