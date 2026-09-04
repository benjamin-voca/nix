#!/usr/bin/env bash
# Workspace bootstrap: clone or verify the canonical Git working tree.
# Never wipe uncommitted local work.
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
REPO_URL="${REPO_URL:-https://forge.voltrum.co/farbeam/upg.git}"
REPO_SSH_HOST_HINT="${REPO_SSH_HOST_HINT:-forge.voltrum.co/farbeam/upg}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
GIT_TOKEN="${GIT_TOKEN:-}"
GIT_USERNAME="${GIT_USERNAME:-oauth2}"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [upg-bootstrap] $*"; }

mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

auth_url() {
  if [[ -n "$GIT_TOKEN" ]]; then
    # Prefer oauth2 token URL form used by Forgejo/Gitea.
    local base="${REPO_URL#https://}"
    echo "https://${GIT_USERNAME}:${GIT_TOKEN}@${base}"
  else
    echo "$REPO_URL"
  fi
}

configure_git() {
  git config --global --add safe.directory "$WORKSPACE" || true
  git config --global init.defaultBranch "$DEFAULT_BRANCH"
  # Avoid interactive prompts in the pod.
  git config --global credential.helper store || true
  git lfs install --force --skip-repo >/dev/null 2>&1 || git lfs install --force >/dev/null 2>&1 || true
}

has_uncommitted() {
  [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]
}

verify_remote() {
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    log "ERROR: origin remote missing"
    return 1
  fi
  # Accept either bare host path or tokenized URL containing the same path.
  if [[ "$url" != *"$REPO_SSH_HOST_HINT"* && "$url" != *"farbeam/upg"* ]]; then
    log "ERROR: origin does not point at farbeam/upg (got: $url)"
    return 1
  fi
  return 0
}

safe_ff_pull() {
  git fetch --prune origin
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  if git rev-parse --verify "origin/${branch}" >/dev/null 2>&1; then
    if ! git merge --ff-only "origin/${branch}"; then
      log "ERROR: cannot fast-forward onto origin/${branch}; leaving local work intact"
      return 1
    fi
  fi
}

configure_git

if [[ ! -d "$WORKSPACE/.git" ]]; then
  # Empty or non-git directory. Ignore ext4 lost+found on fresh PVCs.
  extras="$(ls -A "$WORKSPACE" 2>/dev/null | grep -Ev '^(\.|lost\+found$)' || true)"
  if [[ -n "$extras" ]]; then
    log "ERROR: $WORKSPACE has files but is not a git checkout; refusing to wipe"
    ls -la "$WORKSPACE" | head -n 50 || true
    exit 1
  fi
  rm -rf "$WORKSPACE/lost+found" 2>/dev/null || true

  log "cloning $REPO_URL (branch=$DEFAULT_BRANCH)"
  # Clone into a temp dir then move, so a failed clone doesn't leave a half tree
  # marked as the workspace root incorrectly.
  rm -rf /tmp/upg-clone
  git clone --branch "$DEFAULT_BRANCH" "$(auth_url)" /tmp/upg-clone
  # Move contents including .git into workspace.
  shopt -s dotglob
  mv /tmp/upg-clone/* "$WORKSPACE"/
  shopt -u dotglob
  rm -rf /tmp/upg-clone
  # Rewrite origin to the non-token URL; credentials come from insteadOf.
  git remote set-url origin "$REPO_URL"
  if [[ -n "$GIT_TOKEN" ]]; then
    git config "url.$(auth_url).insteadOf" "$REPO_URL"
  fi
  git lfs install --force
  git lfs pull || true
  mkdir -p "$WORKSPACE/UltimateBladeGrounds"
  # SFTPGo runs as uid 1000; make the tree writable for artists.
  chown -R 1000:1000 "$WORKSPACE" || true
  log "clone complete at $(git rev-parse --short HEAD)"
  exit 0
fi

log "existing checkout detected"
verify_remote

# Ensure insteadOf for token auth on existing checkouts.
if [[ -n "$GIT_TOKEN" ]]; then
  git config "url.$(auth_url).insteadOf" "$REPO_URL"
fi

git lfs install --force
git remote set-url origin "$REPO_URL"

if has_uncommitted; then
  log "WARNING: uncommitted local changes present; skipping pull to preserve data"
  git status --short | head -n 50 || true
  chown -R 1000:1000 "$WORKSPACE" || true
  exit 0
fi

if ! safe_ff_pull; then
  exit 1
fi

git lfs pull || true
mkdir -p "$WORKSPACE/UltimateBladeGrounds"
chown -R 1000:1000 "$WORKSPACE" || true
log "workspace ready at $(git rev-parse --short HEAD) on $(git rev-parse --abbrev-ref HEAD)"
