# ts6-manager — custom backend build

Patched TeamSpeak 6 Manager backend: adds **`!playlist` chat commands** to
music bots (upstream only loads playlists through the web UI).

- Upstream: https://github.com/clusterzx/ts6-manager
- Base commit: see `UPSTREAM_COMMIT` (main at time of patching)
- Patch: `music-commands.patch` — touches only
  `packages/backend/src/voice/music-command-handler.ts`

## Commands added

| Command | Behavior |
|---|---|
| `!playlist` / `!playlist list` | List playlists `[id] name (N tracks)` |
| `!playlist play <id\|name>` | Replace queue, start playing the playlist |
| `!playlist queue <id|name>` | Append the playlist to the current queue (auto-starts if idle) |
| `!playlist add <id\|name>` | Add the **currently playing track** to the playlist (creates the library Song row if missing) |
| `!play <url\|query>` | Non-URL args are treated as a YouTube search — first result plays |
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

## Known limitation: avatar uploads (TS6 beta server)

`!avatar` is implemented (SSH ftinitupload + file-transfer push) but the
TS6 server **beta** rejects avatar-slot uploads from the query interface:
`ftinitupload cid=0` returns `2565 invalid ssize`. The bot CAN initialize
its avatar slot via the voice-protocol ftinitupload, but TS6 does not
return an ftkey over the voice protocol — so the transfer can't complete.
This will work once upstream fixes cid=0 uploads; the code is ready.
