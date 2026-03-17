# Agent Instructions for devpanel/php

This file is the single source of truth for all AI coding agents working in this repository.
GitHub Copilot reads `.github/copilot-instructions.md`, which defers to this file.

## Project Overview

This repository contains Dockerfiles and supporting scripts for building DevPanel PHP Docker images. Three shared image variants are built for each supported PHP version (7.4, 8.0, 8.1, 8.2, 8.3):

- **base** – Full PHP + Apache environment with Code Server, Composer, WP-CLI, and Drush. This is the foundation for all other variants.
- **secure** – Extends `base`, adds ModSecurity (WAF) with the OWASP Core Rule Set.
- **advance** – Extends `secure`, adds Redis and Supervisor for running multiple services.

The shared Dockerfiles live in `base/`, `secure/`, and `advance/` at the repo root and are parameterized by PHP version. Per-version subdirectories (e.g. `8.3/base/`) contain only version-specific override Dockerfiles for cases where a PHP version needs different packages or build steps. The build is orchestrated by `docker-bake.hcl` using Docker BuildKit Bake.

Images are published to Docker Hub as `devpanel/php:<version>-<variant>` (e.g. `devpanel/php:8.3-base`). Release candidates built from the `develop` branch are tagged with `-rc` (e.g. `devpanel/php:8.3-base-rc`).

## Repository Structure

```
base/                         # Shared base Dockerfile (PHP + Apache)
  Dockerfile
  bin/                        # DevPanel CLI binary
  drush/                      # Drush version directories (drush7–drush11)
  scripts/                    # Apache startup scripts
  templates/                  # Apache/PHP config templates
secure/                       # Shared secure Dockerfile (extends base)
  Dockerfile
  templates/                  # ModSecurity config files
advance/                      # Shared advance Dockerfile (extends secure)
  Dockerfile
  scripts/                    # Redis startup script
  supervisor/                 # Supervisor config
<php-version>/                # Per-version override directories (e.g. 7.4, 8.0, 8.1, 8.2, 8.3)
  base/
    Dockerfile                # Version-specific PHP extension/package overrides only
  secure/                     # Only present where the version needs a secure-stage tweak (7.4, 8.0)
    Dockerfile
docker-bake.hcl               # BuildKit Bake file — controls all builds, versions, and tagging
tests/                        # Test and lint scripts
  build-dockerfile.sh
  run-dockerfile.sh
  detect-versions.sh          # Detects which versions/stages are affected by changed files
  baselines/                  # Linting baseline JSON files
test.sh                       # Convenience wrapper: runs yaml/shell/dockerfile/build/run suites
.github/
  workflows/
    docker-build-on-push.yml  # Triggered on push to main/develop; detects changed versions
    docker-build-all.yml      # Manual full rebuild (workflow_dispatch, no cache)
    ci.yml                    # Linting and tests (push + pull_request)
  actions/
    build-php-images/         # Composite action: detect changed versions and run the Docker build
      action.yml
    preseed-downloads/        # Composite action: resolve versions, cache/restore downloads
      action.yml
  copilot-instructions.md     # Points to this file
```

## Tech Stack

- **Base images**: Official `php:<version>-apache` images
- **PHP extensions**: Installed via `docker-php-ext-install`, `docker-php-ext-configure`, and `pecl`
- **Tools included**: Composer (v1 and v2), WP-CLI, Drush (v7–v11), BEE CLI, Code Server
- **Security**: ModSecurity + OWASP CRS (secure/advance variants), optional Polyverse polymorphing
- **Process management**: Apache (base/secure), Supervisor with Redis (advance)
- **CI/CD**: GitHub Actions → Docker Hub (`devpanel/php`)

## Task Planning

Before starting any non-trivial task, create or update `TODO.md` at the repository root with your plan:

1. **List every step** required to complete the task as a checklist (use `- [ ]` / `- [x]` Markdown checkboxes).
2. **Define done** — add a "Definition of Done" subsection that states the concrete, verifiable criteria that must be met before the task is considered complete. Examples:
   - All affected Dockerfiles updated and building without errors.
   - CI workflows pass on the target branch.
   - Documentation and/or `AGENTS.md` updated if conventions changed.
3. **Tick items off** as you complete them and keep `TODO.md` committed so progress is visible in the PR.
4. **Remove or archive** the `TODO.md` file (or clear its contents) once the task is fully done and the PR is merged.

Example `TODO.md` structure:

```markdown
# Task: Bump WP-CLI to v2.10.0

## Steps
- [ ] Update the WP-CLI download URL/version in `base/Dockerfile`
- [ ] Update the WP-CLI version in `7.4/base/Dockerfile` (pinned to an older version for PHP 7.4)

## Definition of Done
- Both Dockerfiles reference the target WP-CLI version.
- CI builds pass for all affected image variants.
```

## Conventions

### General
- All text files must end with a trailing newline. The baseline-generating lint scripts (`tests/lint-dockerfile.sh`, `tests/lint-shell.sh`, `tests/lint-yaml.sh`) enforce this by appending `\n` after every generated JSON baseline.

### Dockerfile Style
- Section headers use `#==` comments (e.g. `#== Install Composer`).
- Each logical step is a separate `RUN` instruction to keep layers clear.
- `ARG` directives are placed immediately before the `RUN` that uses them (e.g. `ARG CODESERVER_VERSION`).
- Tool versions are pinned via `ARG` (e.g. `ARG WP_CLI_VERSION=2.9.0`).
- The default non-root user is `www` (UID/GID 1000). Always switch `USER root` for privileged steps and restore `USER ${USER}` afterward.
- The working directory is `${APP_ROOT}` (`/var/www/html`).
- Clean up temporary files (`/tmp/*`, apt lists) within the same `RUN` layer.

### Adding a New PHP Version
1. Create `<version>/base/Dockerfile` with any PHP-version-specific package or extension differences (copy the closest existing version directory as a starting point).
2. If the new version requires a secure-stage tweak, also create `<version>/secure/Dockerfile`.
3. Add the new version to the `VERSIONS` variable default in `docker-bake.hcl` and update `LATEST_PHP_VERSION` if it becomes the highest version.
4. Run `./test.sh` to verify linting and build correctness.

### Adding or Updating a Tool
- Update the relevant `ARG <TOOL>_VERSION` value (or the hard-coded version string) in the shared Dockerfile under `base/`, `secure/`, or `advance/`.
- If a per-version override Dockerfile in `<version>/base/` also references the tool (e.g. PHP 7.4 pins an older version), update it there too.

### GitHub Actions

#### Composite Actions
- **`.github/actions/build-php-images`** — detects changed PHP versions and runs `docker buildx bake` using `docker-bake.hcl`. Called directly by the trigger workflows below.
- **`.github/actions/preseed-downloads`** — resolves code-server and Copilot Chat versions, restores/downloads artifacts into `$RUNNER_TEMP/build-downloads/pre-downloaded/`, and exposes `DOWNLOADS_DIR` + SHA256 outputs for Docker builds.

#### Workflows
- **`docker-build-on-push.yml`** — triggered on pushes to `main` or `develop`; uses `tests/detect-versions.sh` to determine which versions/stages are affected, then calls `.github/actions/build-php-images` with caching enabled.
- **`docker-build-all.yml`** — manual `workflow_dispatch` trigger to rebuild all images without cache.
- **`ci.yml`** — runs YAML, shell, and Dockerfile linting plus build/run tests on pushes and pull requests.
- Production images are tagged without suffix (e.g. `devpanel/php:8.3-base`); `develop` branch builds use the `-rc` suffix.
- Required repository secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`. Optional: `GHCR_TOKEN` (falls back to `GITHUB_TOKEN` for GHCR pushes).

## Environment Variables (base images)

| Variable | Default | Purpose |
|---|---|---|
| `APP_ROOT` | `/var/www/html` | Application root and web root |
| `PHP_MEMORY_LIMIT` | `4096M` | PHP memory limit |
| `PHP_MAX_EXECUTION_TIME` | `600` | PHP max execution time |
| `PHP_UPLOAD_MAX_FILESIZE` | `64M` | Upload file size limit |
| `CODES_PORT` | `8080` | Code Server port |
| `CODES_ENABLE` | `yes` | Enable/disable Code Server |

## Pull Request Guidelines

- Keep changes focused: update one PHP version or one variant at a time when possible.
- If a change applies to all versions (e.g. bumping a shared tool version), update the shared Dockerfile(s) in `base/`, `secure/`, or `advance/` — plus any per-version overrides that pin a different value.
- Describe which image tags are affected in the PR description.
- Verify the Docker build locally before opening a PR: `docker buildx bake --no-push` (uses `docker-bake.hcl`), or run `./test.sh` for full linting and build tests.
