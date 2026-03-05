# Copilot Instructions for devpanel/php

## Project Overview

This repository contains Dockerfiles and supporting scripts for building DevPanel PHP Docker images. Each PHP version (7.4, 8.0, 8.1, 8.2, 8.3) provides three image variants:

- **base** – Full PHP + Apache environment with Code Server, Composer, WP-CLI, and Drush. This is the foundation for all other variants.
- **secure** – Extends `base`, adds ModSecurity (WAF) with the OWASP Core Rule Set.
- **advance** – Extends `secure`, adds Redis and Supervisor for running multiple services.

Images are published to Docker Hub as `devpanel/php:<version>-<variant>` (e.g. `devpanel/php:8.3-base`). Release candidates built from the `develop` branch are tagged with `-rc` (e.g. `devpanel/php:8.3-base-rc`).

## Repository Structure

```
<php-version>/          # e.g. 7.4, 8.0, 8.1, 8.2, 8.3
  base/
    Dockerfile
    bin/                # DevPanel CLI binary
    drush/              # Drush version directories (drush7–drush11)
    scripts/            # Apache startup scripts
    templates/          # Apache/PHP config templates
  secure/
    Dockerfile
    templates/          # ModSecurity config files
  advance/
    Dockerfile
    scripts/            # Redis startup script
    supervisor/         # Supervisor config
.github/
  workflows/            # CI/CD workflows (one per version × variant)
```

## Tech Stack

- **Base images**: Official `php:<version>-apache` images
- **PHP extensions**: Installed via `docker-php-ext-install`, `docker-php-ext-configure`, and `pecl`
- **Tools included**: Composer (v1 and v2), WP-CLI, Drush (v7–v11), BEE CLI, Code Server
- **Security**: ModSecurity + OWASP CRS (secure/advance variants), optional Polyverse polymorphing
- **Process management**: Apache (base/secure), Supervisor with Redis (advance)
- **CI/CD**: GitHub Actions → Docker Hub (`devpanel/php`)

## Conventions

### Dockerfile Style
- Section headers use `#==` comments (e.g. `#== Install Composer`).
- Each logical step is a separate `RUN` instruction to keep layers clear.
- `ARG` directives are placed immediately before the `RUN` that uses them (e.g. `ARG CODESERVER_VERSION`).
- Tool versions are pinned via `ARG` (e.g. `ARG WP_CLI_VERSION=2.9.0`).
- The default non-root user is `www` (UID/GID 1000). Always switch `USER root` for privileged steps and restore `USER ${USER}` afterward.
- The working directory is `${APP_ROOT}` (`/var/www/html`).
- Clean up temporary files (`/tmp/*`, apt lists) within the same `RUN` layer.

### Adding a New PHP Version
1. Copy an existing version directory (e.g. `8.3/`) as the new version.
2. Update the `FROM php:<new-version>-apache` line in `base/Dockerfile`.
3. Adjust `pecl install` package versions as needed for the new PHP version.
4. Create three new GitHub Actions workflows in `.github/workflows/` following the naming pattern `docker-publish-php<version>-<variant>.yml`.
5. Update workflow trigger paths to match the new version directory.

### Adding or Updating a Tool
- Update the relevant `ARG <TOOL>_VERSION` value in the Dockerfile.
- Apply the same change to **all affected PHP version directories** to keep versions consistent.

### GitHub Actions Workflows
- Each workflow triggers on pushes to `main` or `develop` that modify files under the corresponding version/variant directory.
- Production images are tagged without suffix (e.g. `devpanel/php:8.3-base`); release candidates from `develop` use the `-rc` suffix.
- Secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` must be configured in the repository settings.

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
- If a change applies to all versions (e.g. bumping a shared tool version), update all affected Dockerfiles in the same PR.
- Describe which image tags are affected in the PR description.
- Verify the Docker build locally before opening a PR: `docker build -t test -f <version>/<variant>/Dockerfile <version>/<variant>/`.
