#!/usr/bin/env bash
# Download the devpanel CLI for one architecture from devpanel/dp-cli.
#
# Usage:
#   fetch-devpanel.sh <amd64|arm64> <dest-file>
#   fetch-devpanel.sh --self-test
#
# GHCR_TOKEN  When set, download the latest release from
#             https://github.com/devpanel/dp-cli. When unset, keep dest if it
#             is already an executable for the requested architecture.
set -euo pipefail

asset_filter() {
  cat <<'EOF'
def arch_ok:
  if $arch == "amd64" then test("(^|[^A-Za-z0-9])(amd64|x86_64)([^A-Za-z0-9]|$)"; "i")
  elif $arch == "arm64" then test("(^|[^A-Za-z0-9])(arm64|aarch64)([^A-Za-z0-9]|$)"; "i")
  else false
  end;
def skip:
  test("\\.(sha256|sha512|sum|txt|md|sig|pem|sbom|json|yml|yaml)$"; "i")
  or test("checksum|provenance|intoto"; "i");
def other_os:
  test("darwin|macos|windows|freebsd|android|\\.exe$"; "i");
(
  [ .assets[]?
    | select(.name | skip | not)
    | select(.name | other_os | not)
    | select(.name | arch_ok)
  ]
  | sort_by(
      (if (.name | test("musl|alpine"; "i")) then 1 else 0 end),
      (if (.name | test("devpanel"; "i")) then 0 else 1 end),
      (if (.name | test("\\.(tar\\.gz|tgz|tar\\.xz|txz|zip|deb)$"; "i")) then 1 else 0 end),
      (.name | length),
      .name
    )
  | .[0]
) as $asset
| if $asset == null then empty else [$asset.id, $asset.name, $asset.url] | @tsv end
EOF
}

elf_matches() {
  local desc="$1"
  local want="$2"
  local lower
  lower=$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')
  case "$want" in
    amd64) [[ "$lower" == *x86-64* || "$lower" == *x86_64* ]] ;;
    arm64) [[ "$lower" == *aarch64* ]] ;;
    *) return 1 ;;
  esac
}

extract_into() {
  local asset_path="$1"
  local extract_dir="$2"
  local kind
  kind=$(file -b "$asset_path")
  mkdir -p "$extract_dir"
  case "$kind" in
    *"gzip compressed"*)
      if tar -tzf "$asset_path" >/dev/null 2>&1; then
        tar -xzf "$asset_path" -C "$extract_dir"
      else
        gzip -dc "$asset_path" > "${extract_dir}/devpanel"
      fi
      ;;
    *"XZ compressed"*)
      tar -xJf "$asset_path" -C "$extract_dir"
      ;;
    *"Zip archive"*)
      unzip -q "$asset_path" -d "$extract_dir"
      ;;
    *"Debian binary package"*)
      dpkg-deb -x "$asset_path" "$extract_dir"
      ;;
    "ELF "*)
      cp "$asset_path" "${extract_dir}/devpanel"
      ;;
    *)
      echo "ERROR: Unrecognized devpanel asset type: ${kind}" >&2
      return 1
      ;;
  esac
}

choose_elf() {
  local root="$1"
  local want="$2"
  local named="" fallback="" candidate base desc
  while IFS= read -r candidate; do
    [[ -f "$candidate" ]] || continue
    desc=$(file -b "$candidate")
    elf_matches "$desc" "$want" || continue
    base=$(basename "$candidate")
    case "$base" in
      devpanel|dp-cli|dp)
        named=$candidate
        break
        ;;
    esac
    if [[ -z "$fallback" ]]; then
      fallback=$candidate
    fi
  done < <(find "$root" -type f -print)
  if [[ -n "$named" ]]; then
    printf '%s\n' "$named"
  elif [[ -n "$fallback" ]]; then
    printf '%s\n' "$fallback"
  else
    return 1
  fi
}

usage() {
  cat <<'EOF'
Usage: fetch-devpanel.sh <amd64|arm64> <dest-file>
       fetch-devpanel.sh --self-test
EOF
}

self_test() (
  set -euo pipefail
  local json selected name pack archive extract found
  json=$(mktemp)
  trap 'rm -f "$json"' EXIT
  cat >"$json" <<'EOF'
{ "assets": [
  {"id": 1, "name": "checksums.txt", "url": "https://example.test/checksums"},
  {"id": 2, "name": "devpanel-linux-amd64.tar.gz", "url": "https://example.test/amd64-tar"},
  {"id": 3, "name": "devpanel-linux-amd64", "url": "https://example.test/amd64"},
  {"id": 4, "name": "devpanel-linux-arm64", "url": "https://example.test/arm64"},
  {"id": 5, "name": "devpanel-linux-musl-amd64", "url": "https://example.test/musl"},
  {"id": 6, "name": "devpanel-darwin-arm64", "url": "https://example.test/darwin"},
  {"id": 7, "name": "dp-cli_1.4.0_linux_x86_64.tar.gz", "url": "https://example.test/x86"}
]}
EOF
  selected=$(jq -er --arg arch amd64 "$(asset_filter)" "$json")
  name=$(printf '%s' "$selected" | cut -f2)
  [[ "$name" == "devpanel-linux-amd64" ]] || {
    echo "amd64 selection failed: ${name}" >&2
    exit 1
  }
  selected=$(jq -er --arg arch arm64 "$(asset_filter)" "$json")
  name=$(printf '%s' "$selected" | cut -f2)
  [[ "$name" == "devpanel-linux-arm64" ]] || {
    echo "arm64 selection failed: ${name}" >&2
    exit 1
  }

  cat >"$json" <<'EOF'
{ "assets": [
  {"id": 9, "name": "dp-cli_1.4.0_linux_arm64.tar.gz", "url": "https://example.test/arm-tar"},
  {"id": 8, "name": "dp-cli_1.4.0_linux_amd64.tar.gz", "url": "https://example.test/amd-tar"}
]}
EOF
  selected=$(jq -er --arg arch arm64 "$(asset_filter)" "$json")
  name=$(printf '%s' "$selected" | cut -f2)
  [[ "$name" == "dp-cli_1.4.0_linux_arm64.tar.gz" ]] || {
    echo "archive selection failed: ${name}" >&2
    exit 1
  }

  if ! elf_matches "ELF 64-bit LSB executable, x86-64, statically linked" amd64; then
    echo "amd64 ELF match failed" >&2
    exit 1
  fi
  if elf_matches "ELF 64-bit LSB executable, x86-64, statically linked" arm64; then
    echo "arm64 ELF match should reject x86-64" >&2
    exit 1
  fi
  if ! elf_matches "ELF 64-bit LSB executable, ARM aarch64, statically linked" arm64; then
    echo "arm64 ELF match failed" >&2
    exit 1
  fi

  pack=$(mktemp -d)
  archive=$(mktemp)
  extract=$(mktemp -d)
  cp /bin/true "${pack}/devpanel"
  tar -C "$pack" -czf "$archive" devpanel
  extract_into "$archive" "$extract"
  found=$(choose_elf "$extract" amd64)
  [[ "$(basename "$found")" == "devpanel" ]] || {
    echo "extract selection failed: ${found}" >&2
    exit 1
  }
  rm -rf "$pack" "$archive" "$extract"
  echo "self-test ok"
)

http_get() {
  local token="$1"
  local accept="$2"
  local url="$3"
  local out="$4"
  local -a args
  args=(
    -sS -L --retry 5 --retry-all-errors --connect-timeout 20
    -H "Accept: ${accept}"
    -H "User-Agent: devpanel-php-build"
    -o "$out"
    -w "%{http_code}"
  )
  if [[ -n "$token" ]]; then
    args+=(-H "Authorization: Bearer ${token}")
  fi
  curl "${args[@]}" "$url"
}

fetch_release() {
  local out="$1"
  local status
  status=$(http_get "$GHCR_TOKEN" "application/vnd.github+json" "$release_url" "$out" || true)
  if [[ "$status" == "200" ]]; then
    return 0
  fi
  echo "ERROR: GitHub API returned HTTP ${status:-unknown} for ${release_url}." >&2
  if [[ -s "$out" ]]; then
    jq -r '.message // empty' "$out" >&2 || true
  fi
  return 1
}

fail() {
  local reason="$1"
  echo "ERROR: ${reason}" >&2
  echo "::error::${reason}"
  exit 1
}

use_committed_fallback() {
  local reason="$1"
  local desc
  if [[ -n "$dest" && -f "$dest" ]]; then
    desc=$(file -b "$dest")
    if elf_matches "$desc" "$arch"; then
      echo "${reason} Using committed fallback ${dest}."
      exit 0
    fi
    echo "ERROR: Existing ${dest} is not a ${arch} executable (${desc})." >&2
  fi
  fail "$reason"
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit
fi

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 1
fi

arch=$1
dest=$2
case "$arch" in
  amd64|arm64) ;;
  *)
    echo "ERROR: Architecture must be amd64 or arm64 (got '${arch}')." >&2
    exit 1
    ;;
esac

release_url="https://api.github.com/repos/devpanel/dp-cli/releases/latest"

if ! command -v file >/dev/null 2>&1; then
  fail "Required command not found: file"
fi

if [[ -z "${GHCR_TOKEN:-}" ]]; then
  use_committed_fallback "GHCR_TOKEN is unset, so the latest devpanel/dp-cli release was not downloaded."
fi

for cmd in curl jq tar gzip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "Required command not found: ${cmd}"
  fi
done

work=""
trap '[[ -n "${work}" ]] && rm -rf "${work}"' EXIT
work=$(mktemp -d)
release_json="${work}/release.json"

if ! fetch_release "$release_json"; then
  fail "Unable to read the latest devpanel/dp-cli release with GHCR_TOKEN."
fi

selection=""
if ! selection=$(jq -er --arg arch "$arch" "$(asset_filter)" "$release_json"); then
  echo "Release assets:" >&2
  jq -r '.assets[]?.name' "$release_json" >&2 || true
  fail "No ${arch} Linux devpanel asset was found in the latest dp-cli release."
fi

IFS=$'\t' read -r asset_id asset_name asset_url <<<"$selection"
if [[ -z "${asset_url}" || -z "${asset_name}" ]]; then
  fail "Release asset metadata for ${arch} was incomplete."
fi

asset_path="${work}/asset"
download_status=$(http_get "$GHCR_TOKEN" "application/octet-stream" "$asset_url" "$asset_path" || true)
if [[ "$download_status" != "200" ]]; then
  fail "Download of ${asset_name} failed with HTTP ${download_status:-unknown}."
fi

extract_dir="${work}/extract"
if ! extract_into "$asset_path" "$extract_dir"; then
  fail "Could not unpack ${asset_name}."
fi

binary_path=""
if ! binary_path=$(choose_elf "$extract_dir" "$arch"); then
  fail "No ${arch} executable was found inside ${asset_name}."
fi

mkdir -p "$(dirname "$dest")"
mv -f "$binary_path" "$dest"
chmod 0755 "$dest"
tag=$(jq -r '.tag_name // "unknown"' "$release_json")
echo "Installed devpanel ${tag} asset ${asset_id} (${asset_name}) for ${arch} at ${dest}"
