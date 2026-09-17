#!/usr/bin/env bash
# Rebuild the patched ts6-manager backend image and push it to Harbor.
#
# Custom patch: !playlist chat commands for music bots
#   (upstream only loads playlists via the web UI; this adds chat control).
#
# Why this flow: Harbor (10.0.0.56:5000) is only reachable from the cluster
# LAN, not the Mac — so the amd64 image is built on the Mac (buildx/QEMU),
# streamed over SSH to backbone-01, and pushed to Harbor from there
# (root/user docker config on the node has the Harbor credentials).
#
# Usage:  ./build-and-push.sh [tag]     (default tag: 0.1.0-playlist)
set -euo pipefail

TAG="${1:-0.1.0-playlist}"
IMG="10.0.0.56:5000/library/ts6-manager-backend:${TAG}"
HERE="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_COMMIT="$(cat "${HERE}/UPSTREAM_COMMIT")"
WORK="$(mktemp -d /tmp/ts6-manager-build.XXXXXX)"

echo "==> Cloning upstream at ${UPSTREAM_COMMIT}"
git clone -q https://github.com/clusterzx/ts6-manager.git "${WORK}"
git -C "${WORK}" checkout -q "${UPSTREAM_COMMIT}"

echo "==> Applying patch: music-commands.patch"
git -C "${WORK}" apply "${HERE}/music-commands.patch"

echo "==> Building linux/amd64 (buildx/QEMU — slow)"
docker buildx build --platform linux/amd64 \
  -f "${WORK}/Dockerfile.backend" \
  -t "${IMG}" \
  --load "${WORK}"

echo "==> Streaming image to backbone-01 and pushing to Harbor"
docker save "${IMG}" | gzip | ssh backbone01 \
  'gunzip | docker load && docker push '"${IMG}"

echo "==> Digest as seen from the node:"
ssh backbone01 "docker images --digests --format '{{.Repository}}:{{.Tag}} {{.Digest}}' | grep ts6-manager-backend"
echo "Done: ${IMG}"
