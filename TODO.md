# TODO

Use this file to track work that needs to be done. Lint scripts automatically append baseline-cleanup entries here when all violations for a linter reach zero.

# Task: Fix ARM64 builds executing an AMD64-only CLI

## Steps
- [x] Identify the failing instruction and verify the bundled CLI architecture.
- [x] Inspect all seven ARM64 build jobs in run 39835629916; PHP 7.4 and 8.0–8.5 all fail at the same shared `devpanel version` instruction.
- [x] Keep the legacy CLI on AMD64, omit it on ARM64, and document the limitation.
- [x] Add architecture-aware CLI functional checks.
- [x] Run Dockerfile/shell lint, shell syntax, ARM64 Bake parsing, and secret scanning.
- [x] Attempt the PHP 8.5 build; the existing libsodium download returns an incomplete archive before the changed layer.
- [x] Complete independent code review (no significant issues); automated review unavailable and CodeQL has no analyzable changes.

## Definition of Done
- ARM64 builds do not copy or execute the incompatible legacy CLI.
- AMD64 builds still install and verify the bundled CLI.
- Focused checks pass; unavailable full-build verification is explicitly reported.

# Task: Use native ARM runners for ARM64 builds

## Steps
- [x] Inspect platform routing and composite build setup.
- [x] Route ARM64 builds to ARM runners and skip QEMU for native builds.
- [x] Document native runner selection and the cross-platform fallback.
- [x] Run focused workflow checks, secret scanning, and code/security review.

## Definition of Done
- ARM64 build matrix jobs use `ubuntu-24.04-arm`; AMD64 jobs retain `ubuntu-latest`.
- Native ARM64 and AMD64 builds skip QEMU; cross-platform builds retain it.
- Focused validation passes and changed files contain no secrets.

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
- [x] Review Test run 39724432825; Redis 5.3.7 failed on PHP 8.4/8.5, and shared PECL channel refreshes returned malformed XML on multiple versions.
- [x] Upgrade the shared Redis extension to a PHP 8.4-compatible release, retry the shared PECL refresh, and remove redundant per-version refreshes.
- [ ] Validate the follow-up Test run and complete focused checks, secret scanning, and parallel validation.

## Definition of Done
- The CI failures from Test run 39719313157 have targeted fixes.
- The affected image builds and functional tests pass in CI; modified files contain no secrets.

# Task: Address build and Copilot Chat feedback

## Steps
- [x] Inspect the latest CI failures and the ten PR commits.
- [x] Use HTTPS for PECL channel metadata and remove unnecessary extension pins.
- [x] Remove separate Copilot Chat downloads, installation, and verification.
- [x] Run focused lint/build checks and refresh affected baselines; PHP 7.4 Bake build is blocked by sandbox DNS resolution of Debian repositories.
- [x] Scan changed files for secrets; none detected.
- [x] Complete code/security review: independent review found no significant issues and CodeQL reported zero alerts. Test run 39771022231 requires approval before end-to-end builds can be verified.

## Definition of Done
- Builds no longer download or install a separate Copilot Chat extension.
- PECL uses HTTPS channel metadata and unpinned shared extensions.
- Focused checks pass; any unavailable build verification is explicitly reported.

# Task: Fix remaining PEAR and OPcache build failures

## Steps
- [x] Inspect Test run 39771238006 and the twelve PR commits.
- [x] Upgrade PEAR with curl-downloaded local metadata-independent installation.
- [x] Enable OPcache only when it is not already loaded, including built-in PHP 8.5.
- [x] Run Dockerfile/shell lint, shell syntax and Bake parsing; verify the OPcache guard on official PHP 7.4 and 8.5 images. Full PHP 7.4 Bake build is blocked by sandbox Debian DNS resolution.
- [x] Scan for secrets; no secrets detected. Independent review found no significant issues; automated review was unavailable and CodeQL had no analyzable code. Fresh PHP 7.4/8.5 cache initialization checks pass; CI requires approval.

## Definition of Done
- Legacy images use a PEAR release with HTTP chunked response decoding.
- OPcache remains loaded on every PHP version without enabling a nonexistent PHP 8.5 shared module.
- Focused checks pass; any remaining build or CI blockers are explicitly reported.
