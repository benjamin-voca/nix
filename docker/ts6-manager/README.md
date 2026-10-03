# ts6-manager — custom backend build

Patched TeamSpeak 6 Manager backend: adds **`!playlist` chat commands** to
music bots (upstream only loads playlists through the web UI) and reworks
**AutoDJ** track selection.

- Upstream: https://github.com/clusterzx/ts6-manager
- Base commit: see `UPSTREAM_COMMIT` (main at time of patching)
- Patch: `music-commands.patch` — the cumulative diff vs upstream (command
  handler, prisma schema, voice bot/queue/pipeline). NOTE: `main` on the
  Forgejo fork rejects plain `git push --force`; use the `+work:main`
  refspec syntax instead.
- Fork checkout: `ts6-manager-fork/` in this directory (gitignored here,
  remote `origin` points at the Forgejo fork with an embedded token).
  Edit → commit on `main` → push → regenerate the patch:
  `git -C ts6-manager-fork diff $(cat UPSTREAM_COMMIT) HEAD > music-commands.patch`

## AutoDJ rework (0.16.0)

- **Popularity = user requests only.** Weights come from `MusicRequest`
  rows, which only `!play` / web UI plays write. AutoDJ's own placements
  never feed back into the weighting.
- **Temperature sampling.** `weight = (1 + count)^(1/T)`, T = 2 by default:
  a track requested 100× is ~10× as likely as an unrequested one, not 101×.
  The algorithm decides probabilities, never certainties.
- **Non-repeat window.** `!autodj norepeat <0-100>` (default 5): the last n
  aired tracks (user-picked or bot-picked) are excluded from AutoDJ picks.
  Persisted per bot in `MusicBot.autoDjNoRepeat`; `0` disables the window.

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
| `!lib [list\|play <id\|name>]` | List the library (up to 100 tracks) / queue a library track |
| `!lib add <url\|query>` | Download a track straight into the library without playing it |
| `!lib search <text>` | Search library titles and artists |
| `!lib info <id\|name>` | Duration, source, size, added date, source URL |
| `!lib random [1-10]` | Queue n random library tracks (auto-starts if idle) |
| `!lib next <id\|name>` | Slot a library track directly after the current one |
| `!lib all [shuffled]` | Queue the whole library (optionally shuffled) |
| `!lib recent [1-10]` / `!lib top [1-10]` | Recently played / most played (from play history) |
| `!lib stats` | Track count, total duration, disk usage |
| `!lib url <id\|name>` | Show a track's source URL |
| `!lib rename <id\|name> <title>` / `!lib artist <id\|name> <artist>` | Edit metadata |
| `!lib remove <id\|name>` | Delete from library + disk, purge queued copies |
| `!lib verify [prune]` | Find library rows whose file is missing on disk; prune deletes them |
| `!lib dedupe` | Drop duplicate library rows (same file, keeps oldest) |
| `!lib clear confirm` | Delete all library rows for this server (files kept) |
| `!resume` | Resume playback (explicit counterpart to `!pause`'s toggle) |
| `!playnext <url\|query>` | Download a track and slot it directly after the current one |
| `!link` | Paste the source URL of the current track |
| `!botmove <channel>` | Move the bot to another channel |
| `!autodj norepeat <0-100>` | Set the AutoDJ non-repeat window (default 5); `!autodj status` shows it |
| `!help` | Command reference, in-chat |

Resolution: numeric id, case-insensitive full name, then name prefix.

## Hot deploy (no image build)

The backend deployment runs **from git**, not from the image: a `code-sync`
initContainer clones this fork (cluster-internal Forgejo, creds from the
`ts6-manager-git` secret) into an emptyDir seeded with the image's
`node_modules`, generated Prisma client and built `@ts6/common` dist. The
main container runs `tsx watch` plus a git-poll loop (20s) that
`git reset --hard`s to `origin/main` and rebuilds common/prisma client on
change — tsx watch restarts the server the moment files move.

**To ship a backend change: edit → commit on `main` → push. Done.**
Rolling the pod (e.g. `kubectl -n teamspeak rollout restart
deploy/ts6-manager-backend`) re-clones fresh. Regenerate
`music-commands.patch` after pushing so the nix repo stays in sync.

Image builds (below) are only needed for Dockerfile/dependency changes —
e.g. 0.16.2 added `git` for the in-container sync loop.

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
