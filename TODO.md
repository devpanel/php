# TODO

Use this file to track work that needs to be done. Lint scripts automatically append baseline-cleanup entries here when all violations for a linter reach zero.

# Task: Reopen closed CLI update PRs before force-push

## Steps
- [x] Inspect updater workflow and existing control-flow tests.
- [x] Reopen existing closed PRs before force-pushing the update branch.
- [x] Add regression coverage and validate the workflow changes.
- [x] Scan changed files for secrets; none detected.
- [x] Run CodeQL; no alerts were reported.
- [x] Review the final diff, commit, and push.

## Definition of Done
- A closed, unmerged update PR is reopened before the workflow force-pushes its branch.
- The control-flow regression test and relevant workflow validation pass.

# Task: Rebase auto-merge CLI update pull requests

## Steps
- [x] When repository auto-merge is enabled, dispatch Test and request guarded rebase auto-merge without polling or watching Test.
- [x] Preserve the wait-for-Test and rebase-merge fallback when repository auto-merge is disabled; update regression coverage and docs.
- [x] Validate nonblocking auto-merge and fallback paths, YAML, and embedded Bash.
- [x] Request rebase auto-merge using the workflow token and matching its head SHA.
- [x] Cover successful scheduling and failed Test/merge requests; update workflow documentation.
- [x] Run focused regression tests, YAML lint, and embedded Bash validation.
- [x] Check repository prerequisites: rebase merging and auto-merge are enabled.

## Definition of Done
- Protected-branch updates request rebase auto-merge without bypassing branch requirements.
- Auto-merge-enabled repositories do not wait for Test; disabled repositories wait before attempting a rebase merge.
- The PAT remains limited to Test dispatch; direct pushes and revision-cache behavior are unchanged.
- Repository auto-merge must be enabled for PRs that still have outstanding requirements.

# Task: Dispatch CLI updater tests only for protected branches

## Steps
- [x] Keep Test dispatch and waiting in the protected-branch fallback only.
- [x] Update regression coverage and workflow documentation.
- [x] Run focused updater tests, YAML/shell validation, and embedded Bash syntax/ShellCheck; baseline warnings are unchanged.
- [x] Explain that protected-branch PRs are manually merged by maintainers.
- [x] Scan changed files for secrets; none detected. CodeQL reported no alerts.
- [x] Reply to both review comments.

## Definition of Done
- Direct binary pushes do not manually dispatch or wait for Test.
- A protected-branch fallback still creates/updates its PR, then dispatches Test once and waits for its result.
- Focused validation passes and changed files contain no secrets.

# Task: Fix protected-branch CLI updater failure

## Steps
- [x] Use the workflow token for all pushes and PR operations, limiting GHCR_TOKEN to the protected-path Test dispatch.
- [x] Create or update the PR before dispatching Test once and waiting for its head SHA's run.
- [x] Validate revised authentication, new/existing/reopened PR paths, direct pushes, and Test failures; update documentation.
- [x] Diagnose the failing push from Actions logs: the required `Test` check remains expected after dispatching it on a temporary branch.
- [x] Replace the protected-branch retry push with a pull request from the tested temporary branch.
- [x] Save the revision cache only after the target branch is updated; update workflow documentation.
- [x] Validate YAML and shell changes, including Bash syntax for the embedded updater script.
- [x] Scan changed files for secrets; none were detected.
- [x] Run CodeQL; no alerts were reported.

## Definition of Done
- Unprotected branches still receive direct binary updates.
- Protected branches receive a PR rather than a failing direct-push retry.
- Protected-branch updates dispatch Test once, after the PR exists, with the PAT used only for that dispatch.
- The revision cache is not saved until the target branch contains the updated binaries.
- Focused validation passes and changed files contain no secrets.

# Task: Restore branch-aware CLI updates

## Steps
- [x] Restore the dispatch-selected branch for checkout, destination pushes, and revision-cache keys.
- [x] Use a temporary branch and pre-push Test wait only when the direct target push is rejected.
- [x] Update documentation and validate direct/protected success and failure paths; YAML/shell checks pass with only existing baseline warnings.
- [x] Scan changed files for secrets; none found.
- [x] Run CodeQL; no alerts were reported.
- [x] Reply to the review comment.

## Definition of Done
- Unprotected branches receive a direct push without a temporary branch.
- Protected branches are updated only after Test passes on a temporary branch.
- Revision caching remains scoped to the selected branch and follows successful target push.

# Task: Push tested CLI binaries directly to target branch

## Steps
- [x] Test the generated binary commit on a temporary branch, then push the exact tested commit to `main`.
- [x] Remove PR creation and update updater documentation.
- [x] Run focused validation (YAML lint, Bash syntax/ShellCheck, and mocked pass/fail pushes), scan for secrets, and review the diff.
- [x] Run CodeQL; no alerts were reported.

## Definition of Done
- The updater pushes to `main` only after the exact commit passes `Test`.
- The target push is non-force and the cache is saved only after it succeeds.
- Focused validation passes and changed files contain no secrets.

# Task: Wait for CLI updater Test result

## Steps
- [x] Find the newly dispatched Test run for the generated update commit.
- [x] Wait for the run to finish and stop before the revision cache is saved unless Test passes.
- [x] Update workflow documentation and run focused YAML/shell validation plus mocked success/failure paths.
- [ ] Scan changed files for secrets, run CodeQL, and review the final diff.

## Definition of Done
- The updater waits for Test on the generated branch commit and fails unless that run succeeds.
- The revision cache is saved only after Test succeeds.
- Focused validation passes and changed files contain no secrets.

# Task: Fix protected-branch CLI updater failure

## Steps
- [x] Push rebuilt binaries directly to the target branch when permitted; use a temporary branch and create or update a pull request only when branch protection prevents a direct push.
- [x] Dispatch the required `Test` workflow for the update branch before saving the built-revision cache.
- [x] Run focused workflow validation: YAML lint, shell syntax/ShellCheck, and a mocked PR-dispatch fixture.
- [x] Scan changed files for secrets and review the final diff.
- [ ] Run CodeQL and address any actionable findings.

## Definition of Done
- Unprotected target branches receive direct pushes.
- When branch protection prevents a direct push, the generated-binary pull request receives the required `Test` status check.
- Focused validation passes and changed files contain no secrets.

# Task: Restore DevPanel CLI and enable QEMU on ARM runners

## Steps
- [x] Restore unconditional CLI installation and remove architecture-specific omission tests.
- [x] Enable QEMU on ARM runners and document the runtime emulation requirement.
- [x] Restore the Dockerfile lint baseline; YAML/Dockerfile/shell lint, shell syntax and ARM64 Bake parsing pass.
- [x] Scan changed files for secrets (none); independent review found no significant issues. Automated review unavailable; CodeQL has no analyzable changes.
- [x] Record validation limitation: native ARM runner execution cannot be verified in this AMD64-only sandbox.

## Definition of Done
- All image builds install and verify the bundled CLI.
- ARM runners register QEMU before Buildx; native AMD64 builds still skip it.
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

# Task: Rebuild the DevPanel CLI from GitLab

## Steps
- [x] Add a manual workflow based on `main`. The workflow token commits the binaries.
- [x] Resolve and cache the upstream default branch HEAD through authenticated Git access, and skip revisions already built for the destination branch.
- [x] Build linux/amd64 and linux/arm64 in parallel on native runners, then commit both binaries.
- [x] Configure GitLab source-fetch authentication with a `read_repository` token and GitLab's `oauth2` username.
- [ ] Confirm `cmd/devpanel-client`, Go setup, build dependencies and smoke checks against the actual GitLab source.
- [ ] Run the workflow with GitLab credentials and verify both binaries and revision caching.

## Definition of Done
- A cache miss resolves the latest default-branch commit through authenticated Git access, builds both binaries on `ubuntu-26.04` and `ubuntu-26.04-arm`, and commits `base/bin/devpanel-amd64` and `base/bin/devpanel-arm64`.
- GitLab access uses `GITLAB_TOKEN` with `read_repository` access; the built revision is cached after the binaries are committed.

# Task: Fix GitLab CLI HTTPS authentication

## Steps
- [x] Diagnose the cached-revision job's GitLab authentication failure from its Actions logs.
- [x] Use GitLab's documented `oauth2` username with the access token in every Git request.
- [x] Update workflow documentation and run focused validation and secret scanning.

## Definition of Done
- Plan, source fetch, and private-module requests use the same documented GitLab access-token authentication.
- Documentation no longer requires `GITLAB_USER`.
- Focused validation passes and changed files contain no secrets.

# Task: Fix cached DevPanel CLI revision lookup

## Steps
- [x] Resolve the upstream default-branch HEAD through authenticated Git access instead of the GitLab commits API.
- [x] Update the workflow documentation to describe the revised GitLab credential requirements.
- [x] Run focused workflow/shell validation, scan changed files for secrets, and review the final diff.

## Definition of Done
- The plan job gets the upstream default-branch HEAD using the same authenticated Git access required by the build.
- Documentation no longer requires `read_api` for the updater.
- Focused validation passes and changed files contain no secrets.
