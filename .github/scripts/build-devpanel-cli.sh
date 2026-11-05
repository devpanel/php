#!/usr/bin/env bash
# Build one native devpanel CLI binary from a devpanel/cli checkout.
#
# The binary shipped from this source is github.com/devpanel/cli/cmd/devpanel-client.
# The build is native: the workflow chooses an amd64 or arm64 runner, and this
# script compiles for the machine it is running on.
#
# Usage: build-devpanel-cli.sh <source-dir> <dest-file>
#
# GHCR_TOKEN, when set, lets private Go modules download from github.com/devpanel.
set -euo pipefail

self_test() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "${dir}/cmd/other"
  printf 'module example.com/other\n\ngo 1.22\n' >"${dir}/go.mod"
  if bash "$0" "$dir" "${dir}/devpanel" >/dev/null 2>&1; then
    echo "ERROR: self-test expected a missing cmd/devpanel-client to fail." >&2
    exit 1
  fi
  mkdir -p "${dir}/cmd/devpanel-client"
  if bash "$0" "$dir" "${dir}/devpanel" >/dev/null 2>&1; then
    echo "ERROR: self-test expected the wrong Go module to fail." >&2
    exit 1
  fi
  rm -rf "$dir"
  echo "self-test ok"
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit
fi

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <source-dir> <dest-file>" >&2
  exit 1
fi

src=$1
dest=$2

if [[ ! -d "$src" ]]; then
  echo "ERROR: source directory does not exist: ${src}" >&2
  exit 1
fi
src=$(cd "$src" && pwd)

if [[ ! -d "${src}/cmd/devpanel-client" ]]; then
  echo "ERROR: ${src}/cmd/devpanel-client does not exist." >&2
  echo "The devpanel binary from this source is github.com/devpanel/cli/cmd/devpanel-client." >&2
  exit 1
fi
if [[ ! -f "${src}/go.mod" ]]; then
  echo "ERROR: ${src}/go.mod does not exist." >&2
  exit 1
fi
module_path=$(awk '$1 == "module" { print $2; exit }' "${src}/go.mod")
module_path=${module_path#\"}
module_path=${module_path%\"}
if [[ "$module_path" != "github.com/devpanel/cli" ]]; then
  echo "ERROR: expected Go module github.com/devpanel/cli, found '${module_path:-none}'." >&2
  exit 1
fi

token=${GHCR_TOKEN:-}
if [[ -n "$token" ]]; then
  git config --global url."https://x-access-token:${token}@github.com/".insteadOf "https://github.com/"
fi

echo "Building a native binary"
(
  cd "$src"
  env -u GOOS -u GOARCH CGO_ENABLED=0 \
    go build -trimpath -buildvcs=false -o "$dest" ./cmd/devpanel-client
)
chmod 0755 "$dest"
if ! go version -m "$dest" | grep -q 'github.com/devpanel/cli/cmd/devpanel-client'; then
  echo "ERROR: ${dest} is not github.com/devpanel/cli/cmd/devpanel-client." >&2
  exit 1
fi

echo "Checking devpanel version"
"$dest" version
echo "Wrote ${dest}"
