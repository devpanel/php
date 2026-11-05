#!/usr/bin/env bash
# Clone https://github.com/devpanel/cli at one commit.
#
# The destination must be outside this repository so the clone is not part of
# the php checkout. GitHub Actions should pass a directory under RUNNER_TEMP.
#
# Usage: fetch-devpanel-source.sh <dest-dir> <commit-sha>
# GHCR_TOKEN  Token that can read devpanel/cli.
set -euo pipefail

self_test() {
  local repo_root
  repo_root=$(cd "$(dirname "$0")/../.." && pwd)
  if bash "$0" "${repo_root}/devpanel-cli-src" "0123456789abcdef0123456789abcdef01234567" >/dev/null 2>&1; then
    echo "ERROR: self-test expected a destination inside this repository to fail." >&2
    exit 1
  fi
  echo "self-test ok"
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit
fi

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <dest-dir> <commit-sha>" >&2
  exit 1
fi

dest=$1
sha=$2
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "ERROR: commit SHA must be 40 hexadecimal characters." >&2
  exit 1
fi

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
case "$dest" in
  "$repo_root"|"$repo_root"/*)
    echo "ERROR: Clone devpanel/cli outside this repository (got '${dest}')." >&2
    exit 1
    ;;
esac

token=${GHCR_TOKEN:-}
if [[ -z "$token" ]]; then
  echo "ERROR: GHCR_TOKEN is required to read https://github.com/devpanel/cli." >&2
  exit 1
fi

if [[ -e "$dest" ]]; then
  echo "ERROR: destination already exists: ${dest}" >&2
  exit 1
fi

mkdir -p "$(dirname "$dest")"
mkdir "$dest"
git -C "$dest" init
git -C "$dest" remote add origin https://github.com/devpanel/cli.git
git -C "$dest" -c "http.extraheader=AUTHORIZATION: bearer ${token}" \
  fetch --depth 1 origin "$sha"
git -C "$dest" checkout --detach FETCH_HEAD
echo "Cloned devpanel/cli ${sha} to ${dest}"
