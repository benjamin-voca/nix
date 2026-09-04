# UPG collaborative asset storage

Artists edit Blender / Roblox / texture files over **SFTP** (or WebDAV). A
small in-cluster watcher debounces saves and commits + pushes to:

```text
https://forge.voltrum.co/farbeam/upg
```

Git + Git LFS is the version history. Artists never use Git.

```text
Animator  --SFTP-->  SFTPGo  -->  PVC /workspace (git checkout)
                                      ^
                                      |
                                 git-watcher (debounce → commit → push)
```

## How artists connect

### SFTP (preferred)

| Field | Value |
| --- | --- |
| Host | `backbone-01.local` (LAN) or `192.168.1.7` |
| Port | `32202` (NodePort) |
| Protocol | SFTP |
| Username | your artist account (e.g. `klajdi`) |
| Password | issued by ops (from SOPS / password sheet) |
| Remote path | chrooted to `UltimateBladeGrounds` |

macOS: Finder → Go → Connect to Server → `sftp://klajdi@backbone-01.local:32202`
or Cyberduck / Transmit / Mountain Duck.

### WebDAV (optional)

- URL: `https://assets.voltrum.co/webdav` (after Cloudflare tunnel already covers `*.voltrum.co`)
- Same username/password as SFTP

### Admin UI

- `https://assets.voltrum.co/` → SFTPGo web admin (disable public exposure later if undesired)

## Automatic Git history

1. Artist saves a file (e.g. Ctrl+S in Blender).
2. Watcher notes filesystem activity.
3. After **~45s** of quiet:
   - `git add -A`
   - if nothing staged → stop
   - else commit with a summary of changed paths
   - fast-forward pull if possible
   - `git push` to `main`
4. Blender `*.blend1`… backups are **gitignored** (local only).
5. Large binaries (`*.blend`, `*.fbx`, `*.psd`, …) go through **Git LFS**.

Only one Git writer runs (filesystem lock). Concurrent artist saves are folded
into the next debounced commit. Binary merges are not attempted — last save
wins; history keeps prior versions.

## How to add an artist

1. Generate a bcrypt password hash (SFTPGo portable dump format).
2. Add a user object to the SFTPGo users JSON secret with:
   - `username`
   - `password` (bcrypt)
   - `home_dir` (see scoping below)
   - `permissions: { "/": ["*"] }`
3. Update SOPS key `upg-assets-sftpgo-users-json` in `secrets/roles/backbone.yaml`.
4. Redeploy backbone **or** apply the secret and restart the pod:

```bash
kubectl -n upg-assets create secret generic upg-assets-sftpgo-users \
  --from-file=users.json=./users.json \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n upg-assets rollout restart statefulset/upg-assets
```

## How to restrict an artist to a folder

Set `home_dir` to a subdirectory of the workspace, for example:

```text
/workspace/UltimateBladeGrounds/Benimaru
```

SFTPGo chroots the user there. They cannot see sibling characters.

## How to restore an old asset

```bash
# Find history
git log -- UltimateBladeGrounds/Benimaru/Animations/A1/Blender/A1.blend

# Extract one old revision without switching the whole tree
git show <commit>:UltimateBladeGrounds/Benimaru/Animations/A1/Blender/A1.blend > /tmp/A1-restored.blend

# Or restore in place (then let the watcher commit, or commit manually)
git checkout <commit> -- UltimateBladeGrounds/Benimaru/Animations/A1/Blender/A1.blend
```

For LFS files, ensure `git lfs install` / `git lfs pull` on the machine extracting the blob.

## How to inspect failed pushes

```bash
kubectl -n upg-assets logs statefulset/upg-assets -c git-watcher --tail=200
kubectl -n upg-assets exec statefulset/upg-assets -c git-watcher -- \
  git -C /workspace status
kubectl -n upg-assets exec statefulset/upg-assets -c git-watcher -- \
  git -C /workspace log -5 --oneline
```

The watcher **never** force-pushes or `reset --hard`. On divergence it logs
`ERROR: local and remote have diverged` and preserves local files.

## Directory layout

```text
UltimateBladeGrounds/
└── Benimaru/
    ├── Animations/{A1..U4,Idle,M1,Special}/{Blender,Roblox}/
    ├── VFX/...
    ├── SFX/...
    └── RIG/
```

Same convention for Killua, Rayne, Template. Shared locomotion under
`UltimateBladeGrounds/Shared/{Dash,Sprint,Walk}`.

No `Legacy/` directories — Git history replaces them.

## Migration tooling

```bash
# 1) Export from Nextcloud (non-destructive)
./apps/upg-assets/migration/export-from-nextcloud.sh /tmp/upg-nextcloud-export

# 2) Dry-run against a local clone of farbeam/upg
python3 apps/upg-assets/migration/migrate_assets.py \
  --source /tmp/upg-nextcloud-export/UltimateBladeGrounds \
  --extra-source /tmp/upg-nextcloud-export/Klajdi-files \
  --dest /tmp/upg-inspect \
  --dry-run --plan-json /tmp/upg-migration-plan.json

# 3) Apply locally, commit, push (or apply inside the live workspace pod)
python3 apps/upg-assets/migration/migrate_assets.py ... --apply
```

## Kubernetes resources

| Kind | Name | Notes |
| --- | --- | --- |
| Namespace | `upg-assets` | |
| PVC | `upg-workspace` | 100Gi ceph-block, Git working tree |
| PVC | `upg-sftpgo-data` | 1Gi SQLite + host keys |
| ConfigMap | `upg-assets-scripts` | bootstrap + watcher |
| ConfigMap | `upg-sftpgo-config` | sftpgo.json |
| Secret | `upg-assets-git` | Forgejo token |
| Secret | `upg-assets-sftpgo-users` | portable users JSON |
| StatefulSet | `upg-assets` | sftpgo + git-watcher |
| Service | `upg-assets` | NodePort 32202 → SFTP |
| Ingress | `upg-assets-webdav` | `assets.voltrum.co` |

Declarative source: `modules/outputs/bootstrap/upg-assets.nix`.

## Manual steps that cannot be inferred

1. **Share artist passwords** out-of-band (generated into SOPS; not in git plaintext).
2. **Cloudflare TCP hostname** (optional): `assets-sftp.voltrum.co` → NodePort 32202, same pattern as `forge-ssh`.
3. **Redeploy backbone** so `k8s-secrets-inject` loads the new SOPS keys — or apply secrets manually from `apps/upg-assets/secrets/secret.template.yaml`.
4. **Do not delete Nextcloud copies** until migration verification is signed off.
