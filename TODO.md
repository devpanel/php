# TODO

Use this file to track work that needs to be done. Lint scripts automatically append baseline-cleanup entries here when all violations for a linter reach zero.
- [ ] Remove shellcheck baseline comparison: delete tests/baselines/shellcheck-baseline.json and the baseline comparison logic from tests/lint-shell.sh, and update the script to fail when shellcheck reports any violations (fail when the generated JSON is non-empty). After that, any new shellcheck violation will be an immediate CI failure.

## Task: Probe GHCR during seeding and cache results

### Steps
- [x] Add `GHCR_TOKEN` env var to the `Poll and merge manifests` step
- [x] Update `ghcr_repo` and `ghcr_writable` input descriptions
- [x] Add `IMG_GHCR_DIGESTS_FILE` / `IMG_GHCR_PROBED_FILE` to `declare -A` block
- [x] Initialize both files per image in the init loop
- [x] Add `_ghcr_path` global, `GHCR_BEARER`/`GHCR_BEARER_TIME` globals, and `get_ghcr_inspect_token()` helper
- [x] Add per-cycle GHCR probe block (after seeding, before "Process each pending image")
- [x] Extend REFS construction to use GHCR for confirmed-present seeded digests

### Definition of Done
- After seeding, each platform digest is probed against GHCR via an authenticated HEAD request.
- A HTTP 200 result writes the digest to `ghcr-confirmed-{image}.txt` (sourced from GHCR in subsequent `imagetools create` calls) and to `ghcr-probed-{image}.txt` (skip re-probing).
- A HTTP 404 result writes to `ghcr-probed-{image}.txt` only (avoid re-probing but do not source from GHCR).
- Transient probe errors leave the digest unrecorded so the probe retries on the next cycle.
- Both cache files are stored in `DIGESTS_CACHE_DIR` and included in the existing Actions cache save.
- REFS construction uses `GHCR_REPO@digest` for newly-built platforms AND for seeded platforms confirmed present on GHCR.
- Confirmed digests are NOT written to `ghcr-probed`; skip check tests both files, avoiding a redundant double-entry.
- After a successful `imagetools create`, newly-pushed GHCR digests (NEW_PKEYS) are written to `ghcr-confirmed` so they are never re-probed.
- Linting passes (shell, yaml, dockerfile).

