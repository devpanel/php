#!/usr/bin/env bash
# Build the devpanel CLI from a local checkout of https://github.com/devpanel/cli.
#
# The binary shipped in this repository since 2023 is
# github.com/devpanel/cli/cmd/devpanel-client. That is a different program
# from github.com/devpanel/devpanel-cli (the devpanel/dp-cli releases).
#
# Usage: build-devpanel-cli.sh <source-dir> <commit-sha> <git-ref>
#
# Writes base/bin/devpanel-amd64, base/bin/devpanel-arm64, and
# base/bin/devpanel.rev. GHCR_TOKEN, when set, is used so private module
# downloads from github.com/devpanel can authenticate.
#
# REQUIRE_ARM64_RUN=true fails the build when qemu cannot execute the arm64
# binary. Otherwise a missing qemu only checks the ELF header.
set -euo pipefail

self_test() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "${dir}/cmd/other"
  printf 'module example.com/other\n\ngo 1.22\n' >"${dir}/go.mod"
  if bash "$0" "$dir" "0123456789abcdef0123456789abcdef01234567" main >/dev/null 2>&1; then
    echo "ERROR: self-test expected a missing cmd/devpanel-client to fail." >&2
    exit 1
  fi
  mkdir -p "${dir}/cmd/devpanel-client"
  if bash "$0" "$dir" "0123456789abcdef0123456789abcdef01234567" main >/dev/null 2>&1; then
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
  echo "Usage: $0 <source-dir> <commit-sha> <git-ref>" >&2
  exit 1
fi

src=$1
sha=$2
ref=$3
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "ERROR: commit SHA must be 40 hexadecimal characters." >&2
  exit 1
fi
if [[ ! -d "$src" ]]; then
  echo "ERROR: source directory does not exist: ${src}" >&2
  exit 1
fi
src=$(cd "$src" && pwd)

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
out_dir="${repo_root}/base/bin"
mkdir -p "$out_dir"

if [[ ! -d "${src}/cmd/devpanel-client" ]]; then
  echo "ERROR: ${src}/cmd/devpanel-client does not exist." >&2
  echo "The devpanel binary in this repository is github.com/devpanel/cli/cmd/devpanel-client." >&2
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

build_one() {
  local arch=$1
  local dest="${out_dir}/devpanel-${arch}"
  echo "Building linux/${arch} from ${sha}"
  CGO_ENABLED=0 GOOS=linux GOARCH="${arch}" \
    go build -trimpath -buildvcs=false -o "$dest" ./cmd/devpanel-client
  chmod 0755 "$dest"
}

(
  cd "$src"
  build_one amd64
  build_one arm64
)

amd64_desc=$(file -b "${out_dir}/devpanel-amd64")
arm64_desc=$(file -b "${out_dir}/devpanel-arm64")
[[ "$amd64_desc" == *"x86-64"* ]] || {
  echo "ERROR: amd64 build is not an x86-64 executable (${amd64_desc})." >&2
  exit 1
}
[[ "$arm64_desc" == *"ARM aarch64"* || "$arm64_desc" == *"aarch64"* ]] || {
  echo "ERROR: arm64 build is not an aarch64 executable (${arm64_desc})." >&2
  exit 1
}

if ! go version -m "${out_dir}/devpanel-amd64" | grep -q 'github.com/devpanel/cli/cmd/devpanel-client'; then
  echo "ERROR: amd64 binary is not github.com/devpanel/cli/cmd/devpanel-client." >&2
  exit 1
fi
if ! go version -m "${out_dir}/devpanel-arm64" | grep -q 'github.com/devpanel/cli/cmd/devpanel-client'; then
  echo "ERROR: arm64 binary is not github.com/devpanel/cli/cmd/devpanel-client." >&2
  exit 1
fi

echo "Checking linux/amd64 devpanel version"
"${out_dir}/devpanel-amd64" version

qemu=""
if command -v qemu-aarch64 >/dev/null 2>&1; then
  qemu="qemu-aarch64"
elif command -v qemu-aarch64-static >/dev/null 2>&1; then
  qemu="qemu-aarch64-static"
fi
if [[ -n "$qemu" ]]; then
  echo "Checking linux/arm64 devpanel version with ${qemu}"
  "$qemu" "${out_dir}/devpanel-arm64" version
elif [[ "${REQUIRE_ARM64_RUN:-}" == "true" ]]; then
  echo "ERROR: qemu-aarch64 is required to run the arm64 devpanel binary." >&2
  exit 1
else
  echo "qemu-aarch64 is not installed. Checked the arm64 ELF header only."
fi

cat >"${out_dir}/devpanel.rev" <<EOF
${sha}
source: https://github.com/devpanel/cli
ref: ${ref}
EOF

echo "Wrote ${out_dir}/devpanel-amd64, ${out_dir}/devpanel-arm64, and ${out_dir}/devpanel.rev"
