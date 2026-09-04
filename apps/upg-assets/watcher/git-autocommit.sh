#!/usr/bin/env bash
# Debounced Git auto-commit/push watcher for the UPG asset workspace.
# One writer only. Never force-pushes. Never discards local work.
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-45}"
LOCK_FILE="${LOCK_FILE:-/tmp/upg-git-autocommit.lock}"
STATE_DIR="${STATE_DIR:-/var/run/upg-watcher}"
LOG_PREFIX="[upg-watcher]"

mkdir -p "$STATE_DIR"
cd "$WORKSPACE"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $LOG_PREFIX $*"; }

acquire_lock() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "another git mutation is in progress; skipping"
    return 1
  fi
  return 0
}

changed_paths_summary() {
  # Prefer names from the index after add -A
  git diff --cached --name-only | head -n 40
}

guess_attribution() {
  # Best-effort: SFTPGo writes session activity under its data dir when enabled.
  # We keep this optional and never fail the commit if attribution is unavailable.
  local hint_file="$STATE_DIR/last-sftp-user"
  if [[ -f "$hint_file" ]]; then
    tr -d '\n' <"$hint_file"
  fi
}

build_commit_message() {
  local files
  files="$(changed_paths_summary)"
  local who
  who="$(guess_attribution || true)"
  local subject="assets: automatic update"
  if [[ -n "$who" ]]; then
    # Keep subject short; detail goes in the body.
    local sample
    sample="$(echo "$files" | head -n 1 | sed 's#^UltimateBladeGrounds/##' | cut -d/ -f1-3 | tr '\n' ' ')"
    subject="assets(${who}): update ${sample:-workspace}"
  fi

  printf '%s\n\nChanged:\n' "$subject"
  if [[ -z "$files" ]]; then
    echo "- (unspecified)"
  else
    echo "$files" | sed 's/^/- /'
  fi
}

safe_pull() {
  # Fast-forward only. If divergent, log loudly and leave local work intact.
  if ! git fetch --prune origin 2>&1; then
    log "ERROR: git fetch failed"
    return 1
  fi

  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  local upstream="origin/${branch}"

  if ! git rev-parse --verify "$upstream" >/dev/null 2>&1; then
    log "WARNING: no upstream $upstream yet"
    return 0
  fi

  local local_sha remote_sha base_sha
  local_sha="$(git rev-parse HEAD)"
  remote_sha="$(git rev-parse "$upstream")"
  base_sha="$(git merge-base HEAD "$upstream")"

  if [[ "$local_sha" == "$remote_sha" ]]; then
    return 0
  fi

  if [[ "$local_sha" == "$base_sha" ]]; then
    # Remote is ahead and we can fast-forward.
    if git merge --ff-only "$upstream"; then
      log "fast-forwarded to $remote_sha"
      return 0
    fi
    log "ERROR: fast-forward merge failed unexpectedly"
    return 1
  fi

  if [[ "$remote_sha" == "$base_sha" ]]; then
    # Local is ahead; push will handle it.
    return 0
  fi

  log "ERROR: local and remote have diverged (local=$local_sha remote=$remote_sha base=$base_sha)"
  log "ERROR: refusing automatic reconciliation; manual intervention required"
  log "ERROR: local asset files are preserved"
  return 1
}

do_commit_push() {
  if ! acquire_lock; then
    return 0
  fi

  # Include any changes that arrived during debounce.
  git add -A

  if git diff --cached --quiet; then
    log "no staged changes after debounce"
    return 0
  fi

  # Pull before commit only when the index is clean relative to HEAD except staged.
  # We already staged; create the commit first so local work is never discarded,
  # then attempt push (which may need a pull --rebase/--ff). Prefer:
  # commit → pull --ff-only → push. If pull can't ff, abort push loudly.
  local msg
  msg="$(build_commit_message)"
  git -c user.name="${GIT_AUTHOR_NAME:-UPG Assets Bot}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-assets-bot@voltrum.co}" \
      commit -m "$msg"
  log "created commit $(git rev-parse --short HEAD)"

  if ! safe_pull; then
    log "ERROR: post-commit pull failed; commit remains local: $(git rev-parse --short HEAD)"
    return 1
  fi

  if ! git push origin HEAD; then
    log "ERROR: git push failed; commit remains local: $(git rev-parse --short HEAD)"
    return 1
  fi

  log "pushed $(git rev-parse --short HEAD)"
}

arm_timer() {
  local stamp_file="$STATE_DIR/last-event"
  date +%s >"$stamp_file"
}

wait_for_quiet_then_commit() {
  local stamp_file="$STATE_DIR/last-event"
  while true; do
    if [[ ! -f "$stamp_file" ]]; then
      sleep 2
      continue
    fi
    local last now delta
    last="$(cat "$stamp_file")"
    now="$(date +%s)"
    delta=$((now - last))
    if (( delta >= DEBOUNCE_SECONDS )); then
      rm -f "$stamp_file"
      do_commit_push || true
    else
      sleep 2
    fi
  done
}

# Ignore noisy / non-asset paths inside the working tree.
should_ignore_path() {
  local p="$1"
  case "$p" in
    */.git/*|.git/*|*/.git|*.blend1|*.blend2|*.blend3|*.blend4|*.blend5|*.blend[0-9]|*.blend@|*/.DS_Store|.DS_Store|*/sftpgo-data/*)
      return 0
      ;;
  esac
  return 1
}

watch_loop() {
  log "watching $WORKSPACE (debounce=${DEBOUNCE_SECONDS}s)"
  # inotifywait may miss events under heavy write load; polling fallback below.
  if command -v inotifywait >/dev/null 2>&1; then
    inotifywait -m -r -e modify,create,delete,move --format '%w%f' \
      --exclude '(/\./\.git/|\.blend[0-9]$|\.blend@$|\.DS_Store$)' \
      "$WORKSPACE" 2>/dev/null | while read -r path; do
        if should_ignore_path "$path"; then
          continue
        fi
        arm_timer
      done &
    INOTIFY_PID=$!
  else
    log "inotifywait not available; using poll fallback"
  fi

  # Poll fallback: arm once when the tree becomes dirty. Do NOT re-arm every
  # poll while dirty — that would reset the debounce forever.
  (
    local stamp_file="$STATE_DIR/last-event"
    while true; do
      if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
        if [[ ! -f "$stamp_file" ]]; then
          arm_timer
        fi
      fi
      sleep 5
    done
  ) &
  POLL_PID=$!

  wait_for_quiet_then_commit
}

watch_loop
