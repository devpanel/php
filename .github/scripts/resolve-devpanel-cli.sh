#!/usr/bin/env bash
# Resolve the default-branch commit of https://github.com/devpanel/cli.
#
# GHCR_TOKEN    Token that can read that repository.
# GITHUB_OUTPUT When set, receives sha and ref.
set -euo pipefail

token=${GHCR_TOKEN:-}
if [[ -z "$token" ]]; then
  echo "ERROR: GHCR_TOKEN is required to read https://github.com/devpanel/cli." >&2
  echo "::error::GHCR_TOKEN is required to read https://github.com/devpanel/cli."
  exit 1
fi

api_get() {
  local url=$1
  local body code
  body=$(mktemp)
  code=$(
    curl -sS \
      -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -o "$body" \
      -w "%{http_code}" \
      "$url" || true
  )
  if [[ "$code" != "200" ]]; then
    echo "ERROR: GitHub API ${url} returned HTTP ${code:-unknown}." >&2
    jq -r '.message // empty' "$body" >&2 || true
    rm -f "$body"
    return 1
  fi
  cat "$body"
  rm -f "$body"
}

repo_json=$(api_get "https://api.github.com/repos/devpanel/cli") || {
  echo "::error::Unable to read https://github.com/devpanel/cli. GHCR_TOKEN needs access to that repository."
  exit 1
}
ref=$(jq -r '.default_branch // empty' <<<"$repo_json")
if [[ -z "$ref" ]]; then
  echo "ERROR: devpanel/cli did not report a default branch." >&2
  exit 1
fi

encoded_ref=$(jq -rn --arg ref "$ref" '$ref | @uri')
commit_json=$(api_get "https://api.github.com/repos/devpanel/cli/commits/${encoded_ref}") || {
  echo "::error::Unable to resolve devpanel/cli ref '${ref}'."
  exit 1
}
sha=$(jq -r '.sha // empty' <<<"$commit_json")
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "ERROR: devpanel/cli ref '${ref}' did not resolve to a commit." >&2
  exit 1
fi

echo "devpanel/cli ${ref} is ${sha}"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "sha=${sha}"
    echo "ref=${ref}"
  } >>"$GITHUB_OUTPUT"
fi
