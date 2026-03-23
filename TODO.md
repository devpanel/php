# TODO

Use this file to track work that needs to be done. Lint scripts automatically append baseline-cleanup entries here when all violations for a linter reach zero.
- [ ] Remove shellcheck baseline comparison: delete tests/baselines/shellcheck-baseline.json and the baseline comparison logic from tests/lint-shell.sh, and update the script to fail when shellcheck reports any violations (fail when the generated JSON is non-empty). After that, any new shellcheck violation will be an immediate CI failure.

# Task: Fix imagick extension — eliminate duplicate builds

## Steps
- [x] Analyze CI failure: imagick extension not loading in PHP 8.4/8.5 images
- [x] Add imagick (+ libmagickwand-dev, libmagickcore-dev) to `8.4/base/Dockerfile`
- [x] Add imagick (+ libmagickwand-dev, libmagickcore-dev) to `8.5/base/Dockerfile`
- [x] Remove imagick (imagick-3.8.1, libmagickwand-dev, libmagickcore-dev) from `base/Dockerfile` common stage to eliminate duplicate builds
- [x] Add imagick-3.8.1 (+ libmagick*-dev) to `7.4/base/Dockerfile`
- [x] Add imagick-3.8.1 (+ libmagick*-dev) to `8.0/base/Dockerfile`
- [x] Add imagick-3.8.1 (+ libmagick*-dev) to `8.1/base/Dockerfile`
- [x] Add imagick-3.8.1 (+ libmagick*-dev) to `8.2/base/Dockerfile`
- [x] Add imagick (no pin, + libmagick*-dev) to `8.3/base/Dockerfile`
- [x] Update comments in all modified Dockerfiles
- [x] Verify Dockerfile and shell linting passes

## Definition of Done
- imagick is built exactly once per PHP version, only in each per-version Dockerfile
- `base/Dockerfile` common stage does not install imagick or its build deps
- CI functional tests for all PHP versions pass (`imagick extension loaded` ✔)
- All lint checks pass with no new violations
