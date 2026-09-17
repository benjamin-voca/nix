#!/usr/bin/env bash
# Build the patched ts6-manager backend image INSIDE the cluster with kaniko
# ("the mosaic way": no local build, no Mac -> Harbor upload path).
#
# Flow:
#   1. Reads the Forgejo token from sops (never committed).
#   2. Renders kaniko-build-job.yaml (token + tag placeholders).
#   3. Applies the Job and streams logs until it completes.
#
# Prereqs (already done, see README.md):
#   - Forgejo repo Benjamin/ts6-manager-fork with the patched source on main
#   - harbor-registry pull secret in the teamspeak namespace (push creds)
#
# Usage:  ./build-in-cluster.sh [tag]     (default tag: 0.4.0)
set -euo pipefail

TAG="${1:-0.4.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
NIX_REPO="$(cd "$HERE/../.." && pwd)"
JOB_NAME="ts6-manager-build"

FORGE_TOKEN="$(sops -d "${NIX_REPO}/secrets/roles/backbone.yaml" \
  | python3 -c "import yaml,sys;print(yaml.safe_load(sys.stdin)['argocd-forgejo-token'])")"

# Internal Forgejo endpoint — no tunnel, no TLS, LAN speed
CONTEXT="git://http://Benjamin:${FORGE_TOKEN}@forgejo-http.forgejo.svc:3000/Benjamin/ts6-manager-fork.git"
IMAGE="10.0.0.56:5000/library/ts6-manager-backend:${TAG}"

echo "==> Rendering job (tag: ${TAG})"
FORGE_URL="http://Benjamin:${FORGE_TOKEN}@forgejo-http.forgejo.svc:3000/Benjamin/ts6-manager-fork.git"
python3 - "$HERE/kaniko-build-job.yaml" "$FORGE_URL" "$IMAGE" <<'PY'
import sys
tpl = open(sys.argv[1]).read()
rendered = tpl.replace('__FORGE_GIT_URL__', sys.argv[2]).replace('__IMAGE_TAG__', sys.argv[3])
open('/tmp/ts6-kaniko-job.yaml', 'w').write(rendered)
PY

echo "==> (Re)creating job"
kubectl -n teamspeak delete job "${JOB_NAME}" --ignore-not-found --wait=false
kubectl apply -f /tmp/ts6-kaniko-job.yaml
rm -f /tmp/ts6-kaniko-job.yaml

echo "==> Polling (fail-fast: bails the moment the pod fails)"
SEEN=""
DEADLINE=$((SECONDS + 1800))
while [ $SECONDS -lt $DEADLINE ]; do
  POD="$(kubectl -n teamspeak get pod -l job-name="${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -z "$POD" ]; then sleep 3; continue; fi
  PHASE="$(kubectl -n teamspeak get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  EXIT="$(kubectl -n teamspeak get pod "$POD" -o jsonpath='{.status.containerStatuses[?(@.name=="kaniko")].state.terminated.exitCode}' 2>/dev/null || true)"
  if [ "$PHASE" = "Failed" ] || [ -n "$EXIT" ] && [ "$EXIT" != "0" ]; then
    echo "!! Build FAILED (phase=${PHASE} exit=${EXIT}) — last logs:"
    kubectl -n teamspeak logs "$POD" --tail=25 2>/dev/null
    exit 1
  fi
  if [ "$PHASE" = "Succeeded" ] || [ "$EXIT" = "0" ]; then
    echo "==> Build complete: ${IMAGE}"
    exit 0
  fi
  # Print a heartbeat of the latest log line so progress is visible
  LAST="$(kubectl -n teamspeak logs "$POD" -c kaniko --tail=1 2>/dev/null | head -c 120 || true)"
  if [ -n "$LAST" ] && [ "$LAST" != "$SEEN" ]; then
    echo "[$(date +%H:%M:%S)] $LAST"
    SEEN="$LAST"
  fi
  sleep 10
done
echo "!! Timed out after 30m"
exit 1
