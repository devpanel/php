#!/usr/bin/env bash
# Decide whether the committed devpanel binaries need a rebuild.
#
# UPSTREAM_SHA  40-character commit from devpanel/cli.
# FORCE         "true" rebuilds even when that commit is already recorded.
# REV_FILE      Recorded commit. Defaults to base/bin/devpanel.rev.
# BIN_AMD64     Defaults to base/bin/devpanel-amd64.
# BIN_ARM64     Defaults to base/bin/devpanel-arm64.
# GITHUB_OUTPUT When set, receives changed=true or changed=false.
set -euo pipefail

self_test() {
  local dir recorded
  unset GITHUB_OUTPUT
  dir=$(mktemp -d)
  REV_FILE="${dir}/devpanel.rev"
  BIN_AMD64="${dir}/devpanel-amd64"
  BIN_ARM64="${dir}/devpanel-arm64"
  UPSTREAM_SHA="0123456789abcdef0123456789abcdef01234567"
  FORCE=false
  [[ "$(UPSTREAM_SHA="$UPSTREAM_SHA" FORCE="$FORCE" REV_FILE="$REV_FILE" BIN_AMD64="$BIN_AMD64" BIN_ARM64="$BIN_ARM64" bash "$0")" == "true" ]]

  printf '%s\n' "$UPSTREAM_SHA" >"$REV_FILE"
  : >"$BIN_AMD64"
  : >"$BIN_ARM64"
  [[ "$(UPSTREAM_SHA="$UPSTREAM_SHA" FORCE=false REV_FILE="$REV_FILE" BIN_AMD64="$BIN_AMD64" BIN_ARM64="$BIN_ARM64" bash "$0")" == "false" ]]

  recorded="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  printf '%s\n' "$recorded" >"$REV_FILE"
  [[ "$(UPSTREAM_SHA="$UPSTREAM_SHA" FORCE=false REV_FILE="$REV_FILE" BIN_AMD64="$BIN_AMD64" BIN_ARM64="$BIN_ARM64" bash "$0")" == "true" ]]
  [[ "$(UPSTREAM_SHA="$recorded" FORCE=true REV_FILE="$REV_FILE" BIN_AMD64="$BIN_AMD64" BIN_ARM64="$BIN_ARM64" bash "$0")" == "true" ]]

  rm -f "$BIN_ARM64"
  [[ "$(UPSTREAM_SHA="$recorded" FORCE=false REV_FILE="$REV_FILE" BIN_AMD64="$BIN_AMD64" BIN_ARM64="$BIN_ARM64" bash "$0")" == "true" ]]
  rm -rf "$dir"
  echo "self-test ok"
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit
fi

sha=${UPSTREAM_SHA:-}
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "ERROR: UPSTREAM_SHA must be a 40-character commit (got '${sha}')." >&2
  exit 1
fi

rev_file=${REV_FILE:-base/bin/devpanel.rev}
bin_amd64=${BIN_AMD64:-base/bin/devpanel-amd64}
bin_arm64=${BIN_ARM64:-base/bin/devpanel-arm64}

recorded=""
if [[ -f "$rev_file" ]]; then
  recorded=$(awk 'NR==1 { print; exit }' "$rev_file")
fi

changed=true
if [[ "${FORCE:-false}" != "true" && "$recorded" == "$sha" && -f "$bin_amd64" && -f "$bin_arm64" ]]; then
  changed=false
  echo "devpanel binaries already match ${sha}." >&2
else
  echo "devpanel binaries will be rebuilt for ${sha}." >&2
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "changed=${changed}" >>"$GITHUB_OUTPUT"
fi
printf '%s\n' "$changed"
