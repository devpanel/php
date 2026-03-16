#!/usr/bin/env bash
# tests/cleanup-test-images.sh — Remove all locally-loaded devpanel-php-test
# images from the Docker daemon.
#
# Run this after build/run tests to free disk space, or at any time to reset
# the local test image cache.  tests/run-dockerfile.sh automatically removes
# only the images it tested on exit; this script removes everything in the
# devpanel-php-test namespace.
set -euo pipefail

TAG_PREFIX="devpanel-php-test"

mapfile -t images < <(docker images --format '{{.Repository}}:{{.Tag}}' \
  | grep "^${TAG_PREFIX}:" || true)

if [[ ${#images[@]} -eq 0 ]]; then
  echo "No ${TAG_PREFIX}:* images found."
  exit 0
fi

echo "Removing ${#images[@]} image(s): ${images[*]}"
docker image rm --force "${images[@]}"
echo "Done."
