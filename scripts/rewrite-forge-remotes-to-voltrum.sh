#!/usr/bin/env bash
# Rewrite git remotes quadtech.dev → voltrum.co and alias forge SSH hosts.
# Usage:
#   ./rewrite-forge-remotes-to-voltrum.sh           # apply
#   ./rewrite-forge-remotes-to-voltrum.sh --dry-run  # print only
set -euo pipefail

dry=0
[[ "${1:-}" == "--dry-run" ]] && dry=1

FD=$(command -v fd || command -v fdfind || true)
[[ -n "$FD" ]] || { echo "need fd or fdfind in PATH" >&2; exit 1; }

ssh_config="${HOME}/.ssh/config"
if [[ -f "$ssh_config" ]]; then
  python3 - "$ssh_config" "$dry" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
dry = sys.argv[2] == "1"
t = p.read_text()
o = t
if "forge-ssh.voltrum.co" not in t:
    t = t.replace(
        "Host forge-ssh.quadtech.dev",
        "Host forge-ssh.quadtech.dev forge-ssh.voltrum.co gitea-ssh.quadtech.dev gitea-ssh.voltrum.co",
        1,
    )
if "Host forge.voltrum.co" not in t:
    t = t.replace(
        "Host forge.quadtech.dev",
        "Host forge.quadtech.dev forge.voltrum.co",
        1,
    )
t = t.replace("HostName forge-ssh.quadtech.dev", "HostName forge-ssh.voltrum.co")
if t != o:
    print("ssh config: update ~/.ssh/config")
    if not dry:
        p.write_text(t)
else:
    print("ssh config: ok")
PY
else
  echo "ssh config: missing ${ssh_config}"
fi

"$FD" -u '\.git$' "$HOME" \
  -E Library -E node_modules -E .Trash -E Caches -E .cache |
  while IFS= read -r g; do
    r=${g%/}
    r=${r%/.git}
    git -C "$r" remote 2>/dev/null | while read -r n; do
      u=$(git -C "$r" remote get-url "$n") || continue
      nu=${u//quadtech.dev/voltrum.co}
      if [[ "$u" != "$nu" ]]; then
        echo "$r  $n"
        if [[ "$dry" -eq 0 ]]; then
          git -C "$r" remote set-url "$n" "$nu"
        fi
      fi
    done
  done
