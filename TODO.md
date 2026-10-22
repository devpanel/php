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

# Task: Fix Bullseye security package source

## Steps
- [x] Keep the Bullseye main repository on Debian's archive and accept expired metadata.
- [x] Pin the Bullseye security suite to the final available Debian security snapshot.
- [x] Update PHP 7.4 and 8.0 PostgreSQL sources to the PGDG archive.
- [x] Run focused Dockerfile lint/configuration validation and review the final diff.
- [x] Scan changed files for secrets.
- [x] Run parallel code validation.

## Definition of Done
- Bullseye builds use the Debian archive and pinned security snapshot, and PHP 7.4/8.0 use the archived PGDG repository.
- Focused validation passes and changed files contain no secrets.

# Task: Fix failing Test workflow

## Steps
- [x] Identify matrix failures from GitHub Actions logs.
- [x] Use `--force` in the Copilot Chat functional test to handle a newer preinstalled extension.
- [x] Keep PHP 8.1 extension installation failures from being hidden by the optional dependency-marking fallback.
- [x] Point Bullseye PostgreSQL client installs at the PGDG archive.
- [x] Refresh PECL channel metadata before extension installs.
- [x] Scope the best-effort apt-mark fallback in all PHP version Dockerfiles.
- [x] Run Dockerfile/shell lint, shell syntax, Bake checks, and secret scanning; attempt a PHP 8.1 image build (sandbox DNS prevented GitHub download).
- [x] Run parallel code/security validation; no review findings, and CodeQL had no analyzable code.
- [ ] Confirm the current Test run after approval (run 39724221886 is action-required and has not started jobs).

## Definition of Done
- The CI failures from Test run 39719313157 have targeted fixes.
- The affected image builds and functional tests pass in CI; modified files contain no secrets.
