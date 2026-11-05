#!/usr/bin/env bash
# Build one native devpanel CLI binary from a devpanel/cli checkout.
#
# The binary shipped from this source is github.com/devpanel/cli/cmd/devpanel-client.
# Run this on the runner that matches arch. An amd64 runner builds amd64 and
# an arm64 runner builds arm64.
#
# Usage: build-devpanel-cli.sh <source-dir> <amd64|arm64> <dest-file>
#
# GHCR_TOKEN, when set, lets private Go modules download from github.com/devpanel.
set -euo pipefail

self_test() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "${dir}/cmd/other"
  printf 'module example.com/other\n\ngo 1.22\n' >"${dir}/go.mod"
  if bash "$0" "$dir" amd64 "${dir}/devpanel" >/dev/null 2>&1; then
    echo "ERROR: self-test expected a missing cmd/devpanel-client to fail." >&2
    exit 1
  fi
  mkdir -p "${dir}/cmd/devpanel-client"
  if bash "$0" "$dir" amd64 "${dir}/devpanel" >/dev/null 2>&1; then
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

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <source-dir> <amd64|arm64> <dest-file>" >&2
  exit 1
fi

src=$1
arch=$2
dest=$3
case "$arch" in
  amd64|arm64) ;;
  *)
    echo "ERROR: Architecture must be amd64 or arm64 (got '${arch}')." >&2
    exit 1
    ;;
esac

host_machine=$(uname -m)
case "$host_machine" in
  x86_64) host_arch=amd64 ;;
  aarch64|arm64) host_arch=arm64 ;;
  *)
    echo "ERROR: Unsupported runner machine '${host_machine}'." >&2
    exit 1
    ;;
esac
if [[ "$host_arch" != "$arch" ]]; then
  echo "ERROR: This runner is ${host_arch}. Build ${arch} on a ${arch} runner." >&2
  exit 1
fi

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

echo "Building linux/${arch}"
(
  cd "$src"
  CGO_ENABLED=0 GOOS=linux GOARCH="${arch}" \
    go build -trimpath -buildvcs=false -o "$dest" ./cmd/devpanel-client
)
chmod 0755 "$dest"

desc=$(file -b "$dest")
if [[ "$arch" == "amd64" && "$desc" != *"x86-64"* ]]; then
  echo "ERROR: amd64 build is not an x86-64 executable (${desc})." >&2
  exit 1
fi
if [[ "$arch" == "arm64" && "$desc" != *"aarch64"* ]]; then
  echo "ERROR: arm64 build is not an aarch64 executable (${desc})." >&2
  exit 1
fi
if ! go version -m "$dest" | grep -q 'github.com/devpanel/cli/cmd/devpanel-client'; then
  echo "ERROR: ${dest} is not github.com/devpanel/cli/cmd/devpanel-client." >&2
  exit 1
fi

echo "Checking devpanel version"
"$dest" version
echo "Wrote ${dest}"
