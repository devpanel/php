# TODO

Use this file to track work that needs to be done. Lint scripts automatically append baseline-cleanup entries here when all violations for a linter reach zero.
- [ ] Remove shellcheck baseline comparison: delete tests/baselines/shellcheck-baseline.json and the baseline comparison logic from tests/lint-shell.sh, and update the script to fail when shellcheck reports any violations (fail when the generated JSON is non-empty). After that, any new shellcheck violation will be an immediate CI failure.

# Task: Fix PHP functional test failures for PHP 8.4/8.5

## Steps
- [x] Analyze CI failure: imagick extension not loading in PHP 8.4/8.5 images
- [x] Add imagick (+ libmagickwand-dev, libmagickcore-dev) to `8.4/base/Dockerfile`
- [x] Add imagick (+ libmagickwand-dev, libmagickcore-dev) to `8.5/base/Dockerfile`
- [x] Verify Dockerfile and shell linting passes

## Definition of Done
- `8.4/base/Dockerfile` and `8.5/base/Dockerfile` explicitly install imagick in the per-version RUN layer
- CI functional tests for PHP 8.4 and PHP 8.5 pass (`imagick extension loaded` ✔)
- All lint checks pass with no new violations
