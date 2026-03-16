# devpanel/php

PHP Docker images for [DevPanel](https://devpanel.com) — multi-version,
multi-variant images covering PHP 7.4 through 8.3 with Apache, ModSecurity,
Redis, code-server (VS Code in the browser), Composer, Drush, WP-CLI and more.

---

## Table of Contents

- [Image variants](#image-variants)
- [Quick start (users)](#quick-start-users)
- [Environment variables](#environment-variables)
- [Contributing](#contributing)
- [Testing](#testing)
- [CI / CD](#ci--cd)
- [Agent notes](#agent-notes)
- [Code-server artifact pinning](#code-server-artifact-pinning)

---

## Image variants

Each PHP version ships three layered variants.

| Variant   | Tag suffix  | What it adds |
|-----------|-------------|--------------|
| `base`    | `X.Y-base`  | PHP + Apache + code-server + Composer + Drush + WP-CLI |
| `secure`  | `X.Y-secure`| `base` + ModSecurity / OWASP Core Rule Set |
| `advance` | `X.Y-advance`| `secure` + Redis + Supervisor |

Release candidate tags end with `-rc` (e.g. `8.3-base-rc`).

Available PHP versions: **7.4 · 8.0 · 8.1 · 8.2 · 8.3**

---

## Quick start (users)

```bash
# Pull the latest stable PHP 8.3 advance image
docker pull devpanel/php:8.3-advance

# Run with code-server enabled on port 8080
docker run -p 80:80 -p 8080:8080 devpanel/php:8.3-advance
```

Open `http://localhost` for the web application and `http://localhost:8080`
for the browser-based editor.

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `APP_ROOT` | `/var/www/html` | Application root directory |
| `WEB_ROOT` | `$APP_ROOT` | Document root for Apache |
| `PHP_MEMORY_LIMIT` | `4096M` | PHP `memory_limit` |
| `PHP_MAX_EXECUTION_TIME` | `600` | PHP `max_execution_time` |
| `PHP_MAX_INPUT_TIME` | `600` | PHP `max_input_time` |
| `PHP_MAX_INPUT_VARS` | `3000` | PHP `max_input_vars` |
| `PHP_UPLOAD_MAX_FILESIZE` | `64M` | PHP `upload_max_filesize` |
| `PHP_POST_MAX_SIZE` | `64M` | PHP `post_max_size` |
| `PHP_CLEAR_ENV` | `false` | PHP-FPM `clear_env` |
| `SERVER_NAME` | `default` | Apache `ServerName` |
| `GIT_BRANCH` | `master` | Default Git branch |
| `CODES_PORT` | `8080` | code-server listen port |
| `CODES_ENABLE` | `yes` | Set to `no` to disable code-server |
| `CODES_AUTH` | _(unset)_ | Set to `yes` to require a password |

---

## Contributing

### Repository layout

```
<php-version>/
  base/       # Base image sources (per-version overlay)
  secure/     # Secure image sources (per-version overlay)
  advance/    # Advance image sources (per-version overlay)
base/         # Shared base stage sources (common across all versions)
secure/       # Shared secure stage sources
advance/      # Shared advance stage sources
docker-bake.hcl  # Docker Bake build matrix
.github/
  workflows/  # GitHub Actions CI / build workflows
.githooks/    # Git hooks (activated with ./setup-hooks.sh)
tests/
  baselines/           # Stored violation counts for each linter
  detect-versions.sh   # Shared version-detection script (used by tests and CI)
  *.sh                 # Lint, build, and functional test scripts
  compare-baseline.py  # Shared baseline-comparison helper
test.sh           # Run all checks locally
setup-hooks.sh    # Configure Git to use .githooks/ (run once after cloning)
.yamllint.yml     # yamllint configuration
```

### Adding a new PHP version

1. Copy an existing version directory (e.g. `cp -r 8.3 8.4`).
2. Update the `FROM` line and any version-specific package pins.
3. Update `docker-bake.hcl` if any bake variables need adjusting (the matrix
   auto-generates build targets for every `X.Y/` directory; no per-version
   workflow files are needed).
4. Run `./test.sh` to make sure there are no new lint or build violations.
5. If the new Dockerfiles introduce violations that are intentional or
   unavoidable, update the baseline:

   ```bash
   ./test.sh --update-baseline
   git add tests/baselines/
   ```

### Updating a baseline

Run any individual suite with `--update-baseline`:

```bash
bash tests/lint-dockerfile.sh --update-baseline
bash tests/lint-shell.sh      --update-baseline
bash tests/lint-yaml.sh       --update-baseline
```

Or update all baselines at once:

```bash
./test.sh --update-baseline
```

Commit the changed `tests/baselines/*.json` files together with the code
change that justifies the update.

---

## Testing

### Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| `shellcheck` | Shell script linting | `apt install shellcheck` |
| `yamllint` | YAML linting | `pip install yamllint` |
| `docker` **or** `hadolint` | Dockerfile linting | [docker.com](https://docs.docker.com/get-docker/) or [hadolint releases](https://github.com/hadolint/hadolint/releases) |
| `docker` | Docker build tests | [docker.com](https://docs.docker.com/get-docker/) |

### Running all checks

```bash
./test.sh
```

### Running a single suite

```bash
./test.sh yaml        # YAML lint only
./test.sh shell       # Shell lint only
./test.sh dockerfile  # Dockerfile lint only
./test.sh build       # Docker build tests only
./test.sh run         # Docker functional (run) tests only
./test.sh build run --version 8.2  # Build and run tests for a single PHP version
```

### Build tests

`tests/build-dockerfile.sh` builds every Dockerfile in the repository (without
pushing) to verify the images are buildable.  Images are built in dependency
order per PHP version:

```
base  →  secure (--build-arg BASE_IMAGE=<local base>)  →  advance (--build-arg BASE_IMAGE=<local secure>)
```

Locally-created test tags are cleaned up automatically on script exit.

Build tests take several minutes per PHP version because the images download
packages (code-server, composer, etc.).  Run a single version during
development to keep the feedback loop short:

```bash
./test.sh build --version 8.2
```

### Functional (run) tests

`tests/run-dockerfile.sh` starts each built image as a short-lived container
and verifies core tools and extensions are working:

| Variant | Checks |
|---|---|
| `base` | `php --version`, PHP code execution, `composer --version`, `apache2 -v`, `pdo`/`mbstring` extensions |
| `secure` | All base checks + `mod_security2.so` present |
| `advance` | All base checks + `redis-cli --version` |

Run tests require images built by the build suite.  Run both together:

```bash
./test.sh build run --version 8.2
```

> **Tip:** Set `DEVPANEL_BUILD_ON_PUSH=1` before a `git push` to have the
> pre-push hook also run build and functional tests for any changed Dockerfiles.
> By default the hook runs lint only (fast); CI always runs the full suite.

### How baseline tracking works

Lint checks cover **all severities including style warnings**.  Each baseline
file (`tests/baselines/*.json`) records the number of times each lint rule
fires per file.  A check **fails only when the count for any rule/file pair
*increases* above its baseline value** — or when a rule appears in a file
where it was not present before.  Reducing violations (improving the code) is
always accepted silently.

This means:
- Existing known violations do not block your push or the CI build.
- Any *new* violation introduced by your change will block the push and must
  be fixed (or explicitly added to the baseline with a justification commit).

### Installing the Git pre-push hook

```bash
./setup-hooks.sh
```

This sets `core.hooksPath = .githooks` in the local Git config so the hooks
in `.githooks/` are used directly — no copying needed.  The hooks stay in
sync with the repository automatically.

After running `setup-hooks.sh`, `git push` will automatically lint only the
files you changed.  Set `DEVPANEL_BUILD_ON_PUSH=1` to also run Docker build
and functional tests for any changed Dockerfiles.

---

## CI / CD

### Workflow overview

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci.yml` | push / pull_request to `main`, `develop` | Lint, build & functional checks (required) |
| `docker-build-on-push.yml` | push to `main` or `develop` | Detect changed versions and build images |
| `docker-build-all.yml` | `workflow_dispatch` | Build all versions unconditionally |

`ci.yml` runs lint, build, and functional tests in parallel.  Configure branch protection
rules in GitHub to require all `ci.yml` status checks to pass before pull
requests to `main` or `develop` can be merged, ensuring no broken Dockerfile
or script reaches the publish workflows.  See the
[GitHub docs on required status checks](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches#require-status-checks-before-merging)
for setup instructions.

### Secrets required

| Secret | Description |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |

---

## Agent notes

- Source files live under both per-version directories (`7.4/`, `8.0/`, …) and
  shared top-level directories (`base/`, `secure/`, `advance/`).  Changes to
  a shared directory affect all versions; changes under `X.Y/` affect only
  that version.  Version selection for both local tests and CI is handled by
  `tests/detect-versions.sh`.
- Lint baselines are stored as JSON in `tests/baselines/`.  Update them with
  `./test.sh --update-baseline` whenever you make a change that intentionally
  alters lint counts.
- Build tests (`tests/build-dockerfile.sh`) try to build every Dockerfile
  without pushing.  Functional tests (`tests/run-dockerfile.sh`) then start each
  built image and verify PHP, Apache, Composer, and extensions work.
  Run `./test.sh build run --version <v>` to test a single PHP version quickly.
- Build workflows are `docker-build-on-push.yml` (push-triggered) and
  `docker-build-all.yml` (manual dispatch).  Both call the reusable workflow
  `build-php-images.yml` which performs detect → build.
- The `advance` variant depends on `secure`, which depends on `base`.
  The build chain is enforced via the bake target dependency graph.

---

## Code-server artifact pinning

`base/Dockerfile` files define `CODESERVER_PINNED_HASH_VERSION` (currently `4.99.4`) and use it as the default `CODESERVER_VERSION`.
Checksum verification is applied when `CODESERVER_VERSION` matches `CODESERVER_PINNED_HASH_VERSION`.

For the pinned hash version, keep both hashes in sync:

- `CODESERVER_DEB_SHA256_AMD64`
- `CODESERVER_DEB_SHA256_ARM64`

If you choose to pin another version the same way, compute new hashes with:

```bash
VERSION=4.99.4
for arch in amd64 arm64; do
	TMPDIR=$(mktemp -d)
	curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 \
		"https://github.com/coder/code-server/releases/download/v${VERSION}/code-server_${VERSION}_${arch}.deb" \
		-o "${TMPDIR}/code-server_${VERSION}_${arch}.deb"
	shasum -a 256 "${TMPDIR}/code-server_${VERSION}_${arch}.deb"
	rm -rf "${TMPDIR}"
done
```

Then update each `*/base/Dockerfile` so the version condition and both SHA256 values stay in sync.

Example pattern used in `base/Dockerfile` files:

```dockerfile
if [ "$CODESERVER_VERSION" = "$CODESERVER_PINNED_HASH_VERSION" ]; then \
	case "$DEB_ARCH" in \
		amd64) DEB_SHA256="$CODESERVER_DEB_SHA256_AMD64" ;; \
		arm64) DEB_SHA256="$CODESERVER_DEB_SHA256_ARM64" ;; \
	esac; \
	echo "$DEB_SHA256  /tmp/code-server.deb" | sha256sum -c -; \
fi; \
dpkg -i /tmp/code-server.deb
```
