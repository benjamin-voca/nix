# ts6-manager — custom backend build

Patched TeamSpeak 6 Manager backend: adds **`!playlist` chat commands** to
music bots (upstream only loads playlists through the web UI).

- Upstream: https://github.com/clusterzx/ts6-manager
- Base commit: see `UPSTREAM_COMMIT` (main at time of patching)
- Patch: `music-commands.patch` — the cumulative diff vs upstream (command
  handler, prisma schema, voice bot/queue/pipeline). NOTE: `main` on the
  Forgejo fork rejects plain `git push --force`; use the `+work:main`
  refspec syntax instead.

## Commands added

| Command | Behavior |
|---|---|
| `!playlist` / `!playlist list` | List playlists `[id] name (N tracks)` |
| `!playlist play <id\|name>` | Replace queue, start playing the playlist |
| `!playlist queue <id|name>` | Append the playlist to the current queue (auto-starts if idle) |
| `!playlist add <id\|name>` | Add the **currently playing track** to the playlist (creates the library Song row if missing) |
| `!play <url\|query>` | Non-URL args are treated as a YouTube search — first result plays. Ad-hoc tracks land in the library automatically (deduped on `filePath`) |
| `!play <mix-url>` | YouTube mix URLs (`…watch?v=<id>&list=RD…`) start the anchor video and create/reuse a DB playlist named `"<video title> -- mix"` (e.g. `U 96 - Club Bizarre -- mix`). Every track the mix serves is appended to that playlist. Loading is lazy: exactly one track is buffered ahead, the next one is only fetched when the queue runs dry (track end or `!next`) — `!next` skips instantly while the buffer holds, otherwise it loads the next mix song on demand. Active until `!stop`, `!clear all`, `!playlist play <x>`, another mix, or the mix runs dry |
| `!skip [1-25]` | Skip n tracks in one go (default 1) |
| `!clear [all]` | Drop all queued tracks, keep the current one playing. `!clear all` also stops playback |
| `!queue remove <n\|a-b\|text\|all>` | Remove by position, 1-based inclusive range, or title/artist substring match. `all` = keep-current clear. The playing track is never dropped by range/text/all |
| `!lib [play <id\|name>]` | List the library (up to 100 tracks) / queue a library track |
| `!help` | Command reference, in-chat |

Resolution: numeric id, case-insensitive full name, then name prefix.

## Rebuild / release (in-cluster kaniko — preferred)

```bash
./build-in-cluster.sh [tag]
```

Renders `kaniko-build-job.yaml` with the Forgejo token (from sops, never
committed), runs a kaniko Job in the cluster that clones the patched fork
from **Forgejo** (`Benjamin/ts6-manager-fork`, internal service endpoint)
and pushes straight to **Harbor**. Fail-fast polling: a broken build
surfaces in seconds, not after a 15m log stream.

First-time setup already done: fork repo created on Forgejo and the patched
source pushed to `main` (via `ssh -J backbone01 -p 32222` — the tunnel
drops large pushes; the SSH nodeport is only reachable from the node, hence
the jump).

After building: bump the tag in
`modules/outputs/bootstrap/ts6-manager.nix`, rebuild + apply.

## Legacy: build on the Mac, push from the node

```bash
./build-and-push.sh [tag]
```

Clones upstream at the pinned commit, applies the patch, builds
linux/amd64 via buildx (Mac is arm64 — QEMU, takes a few minutes), streams
the tarball over SSH to backbone-01 and pushes to Harbor from there
(Harbor is not routable from the Mac).

## Why no upstream PR?

Could be upstreamed — the handler mirrors the `/queue/playlist` API route.
Candidate for a PR to clusterzx/ts6-manager if we feel like it.

## Avatar provisioning (TS6 beta server)

The bot's avatar is provisioned **declaratively** — the TS6 beta cannot do
avatar uploads properly:
- WebQuery API keys are scope-blocked from all `ft*` commands
- Voice-protocol `ftinitupload` allocates the avatar slot but returns no
  ftkey, so the transfer can never complete
- SSH-query `ftinitupload cid=0` returns `2565 invalid ssize` (beta bug)

Mechanism (all in `modules/outputs/bootstrap/teamspeak.nix`):
1. The PNG lives sops-encrypted (`ts6-bot-avatar-png` in
   `secrets/roles/backbone.yaml`); `k8s-secrets-inject` creates the
   `ts6-bot-avatar` Secret.
2. The `bot-avatar` initContainer (python:3.12-alpine, digest-pinned) runs
   before the server on every boot: copies the PNG to
   `files/virtualserver_1/internal/avatar_<hash>` on the PVC AND sets
   `client_flag_avatar` in `tsserver.sqlitedb` — the server only advertises
   an avatar when that DB flag is non-empty.

To change the avatar: re-encrypt the new PNG's base64 into the sops key,
`sudo systemctl restart k8s-secrets-inject` on backbone-01, and restart the
teamspeak deployment. Note the hash/uid constants in the initContainer are
the valon bot's identity and stay stable across TS server reinstalls (the
uid comes from the manager bot's identity key).
