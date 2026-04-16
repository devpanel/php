# TODO

Use this file to track work that needs to be done. Lint scripts automatically append baseline-cleanup entries here when all violations for a linter reach zero.
- [ ] Remove shellcheck baseline comparison: delete tests/baselines/shellcheck-baseline.json and the baseline comparison logic from tests/lint-shell.sh, and update the script to fail when shellcheck reports any violations (fail when the generated JSON is non-empty). After that, any new shellcheck violation will be an immediate CI failure.

## Task: Probe GHCR during seeding and cache results

### Steps
- [x] Add `GHCR_TOKEN` env var to the `Poll and merge manifests` step
- [x] Update `ghcr_repo` and `ghcr_writable` input descriptions
- [x] Add the per-image `ghcr-probe-{image}.txt` cache file to the `declare -A` block
- [x] Initialize the single GHCR probe cache file per image in the init loop
- [x] Add `_ghcr_path` global, `GHCR_BEARER`/`GHCR_BEARER_TIME` globals, and `get_ghcr_inspect_token()` helper
- [x] Add per-cycle GHCR probe block (after seeding, before "Process each pending image")
- [x] Extend REFS construction to use GHCR for seeded digests recorded as `found` in the probe cache

### Definition of Done
- After seeding, each platform digest is probed against GHCR via an authenticated HEAD request.
- A HTTP 200 result writes `digest<TAB>found` to `ghcr-probe-{image}.txt`.
- A HTTP 404 result writes `digest<TAB>missing` to `ghcr-probe-{image}.txt`.
- Transient probe errors leave the digest unrecorded so the probe retries on the next cycle.
- The probe cache file is stored in `DIGESTS_CACHE_DIR` and included in the existing Actions cache save.
- The probe cache is cleared (like `IMG_PLATFORM_DIGESTS`) on seeding `ok`/`not_found` and on init corruption to prevent unbounded growth.
- REFS construction uses `GHCR_REPO@digest` for newly-built platforms AND for seeded platforms recorded as `found` in the probe cache.
- Probe cache entries prevent redundant re-probing while preserving retry behavior for transient failures.
- Linting passes (shell, yaml, dockerfile).

