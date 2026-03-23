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

# Task: Fix missing pdo_mysql in PHP 8.5

## Steps
- [x] Identify root cause: `pspell` was removed from PHP 8.4+, causing the common `docker-php-ext-install` command to fail, which left `pdo_mysql` uninstalled for PHP 8.5
- [x] Make `pspell` installation conditional for PHP < 8.4 in `base/Dockerfile`
- [x] Remove `pspell` from the common `docker-php-ext-enable` list (handled in the conditional step)
- [x] Add `pdo_mysql` extension check to `tests/run-dockerfile.sh`
- [x] Move `pspell` fully to per-version Dockerfiles (7.4–8.3); remove all pspell logic from `base/Dockerfile` common stage
- [x] Verify all lint checks pass

## Definition of Done
- `pdo_mysql` is correctly installed and enabled for all PHP versions (7.4–8.5)
- `pspell` is installed only in per-version Dockerfiles for PHP 7.4–8.3 (where the extension source exists); `base/Dockerfile` common stage has no pspell references
- `tests/run-dockerfile.sh` explicitly asserts `pdo_mysql` extension is loaded
- All Dockerfile and shell lint checks pass with no new violations
