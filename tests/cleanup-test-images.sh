#!/usr/bin/env bash
# tests/cleanup-test-images.sh — Remove devpanel-php-test images from the
# Docker daemon.
#
# Usage:
#   tests/cleanup-test-images.sh                  # Remove all devpanel-php-test:* images
#   tests/cleanup-test-images.sh IMAGE [IMAGE...]  # Remove only the specified images
#
# Run this after build/run tests to free disk space, or at any time to reset
# the local test image cache.  tests/run-dockerfile.sh automatically calls
# this script with only the images it tested on exit, leaving any other
# devpanel-php-test:* images intact.  Call without arguments for a full cleanup.
set -euo pipefail

if ! command -v docker &>/dev/null; then
  echo "Error: docker is not installed or not in PATH" >&2
  exit 1
fi

TAG_PREFIX="devpanel-php-test"

if [[ $# -gt 0 ]]; then
  images=("$@")
else
  mapfile -t images < <(docker images --format '{{.Repository}}:{{.Tag}}' \
    | grep "^${TAG_PREFIX}:" || true)
fi

if [[ ${#images[@]} -eq 0 ]]; then
  if [[ $# -gt 0 ]]; then
    echo "Specified images not found or already removed."
  else
    echo "No ${TAG_PREFIX}:* images found."
  fi
  exit 0
fi

echo "Removing ${#images[@]} image(s): ${images[*]}"
docker image rm --force "${images[@]}"
echo "Done."
