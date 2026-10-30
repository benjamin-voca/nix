# Voltrum Motion

Public website: https://motion.voltrum.co. The root Voltrum site is unchanged.
Application source: https://github.com/klajdi-g/Wapper. Public installers are
withdrawn pending rights review and production signing.

`modules/outputs/bootstrap/voltrum-motion.nix` adds
`apps/voltrum-motion/resources.json` to the declarative bootstrap output.
The Kubernetes List defines an isolated `voltrum-motion` namespace with a
content-addressed immutable shell and thumbnail ConfigMaps, two non-root nginx replicas, service,
and ingress. The existing wildcard Cloudflare tunnel routes the hostname to
ingress-nginx; no tunnel or DNS replacement is needed.

Generate updates from the app repository with:

```sh
(cd website && bun install --frozen-lockfile && bun run validate && bun run test:browser)
python3 tools/package-motion-site.py ../nix
```

Use authorized local kubectl credentials to dry-run and apply the generated
List, then verify the rollout and public manifests:

```sh
kubectl apply --server-side --field-manager=voltrum-motion --dry-run=server -f apps/voltrum-motion/resources.json
kubectl apply --server-side --field-manager=voltrum-motion -f apps/voltrum-motion/resources.json
kubectl -n voltrum-motion rollout status deployment/voltrum-motion
curl -f https://motion.voltrum.co/release.json
curl -f https://motion.voltrum.co/catalog.json
```

Server-side apply avoids duplicating the compiled archive into a last-applied
annotation, which exceeds Kubernetes' annotation-size limit for this app/demo.
The October 30 transition used a reviewed one-time ownership adoption for Motion's
site-hash annotation and archive volume from `kubectl-client-side-apply`; normal
rollouts now use the `voltrum-motion` manager without forcing conflicts.
Commit the resulting resources alongside any bootstrap changes. Do not place
credentials, native installers, or downloaded videos in the ConfigMap. Previous
ConfigMaps should remain available while their ReplicaSets are needed. Rollback
is allowed only to a complete snapshot enforcing the current publication policy.
Never roll back to a pre-quarantine snapshot containing unreviewed media or
installer links. Do not use an arbitrary previous ReplicaSet for rollback.

The website source is now React/TypeScript with TanStack Start and Vite. Drizzle
SQLite runs during the catalog import/query/export build step, not in nginx.
Only compiled `website/dist/client/` is packaged. No database, account backend,
source JPEGs/videos, or native installers are added to the cluster. The public
site reads showcase/release manifests from the same origin. Its self-only plus
exact script-hash CSP blocks unapproved external scripts, including the
Cloudflare-injected analytics beacon observed during earlier browser checks.

As of October 30, 2026, the shared app-repository `website/media-policy.json` is
paused with `allowNativeDownloads: false` and `approvedMedia: []`. No real IDs are
approved. Public `catalog.json` is `[]` and `release.json` has no downloads.
The old NASA candidate catalog is not used by the new showcase. A separate
`showcase.json` contains all 353 user-requested cached thumbnails, Cat Pond first,
selected in `website/showcase-selection.json`. Aurora is removed from the website.
The CSP enforces `media-src 'none'` and `img-src 'self'`. This thumbnail-only
selection is not legal clearance; original creators/reuse rights remain unverified.
No remote video URLs, playback, or downloads are exposed. The loopback-only command
`bun run dev:recovered` displays 353 cached original-app thumbnails locally;
never expose that server or publish `.generated/`, its database, or recovered
image screenshots outside the explicit selection. Production packaging rejects
local builds, unselected IDs, modified provenance, video URLs/files, source JPEGs,
and changed prepared thumbnail bytes. Never publish source manifests directly.
Each archive is below 700,000 bytes; the shell and every thumbnail shard share a
snapshot hash and a projected volume. The init container extracts all archives.
Keep the complete matching ConfigMap set for rollback. The Library is browser-local
favorites with search/categories and hash/history navigation, not a new backend.

Native 0.2.2 is a local-only demo/import build with zero bundled remote entries.
Earlier 0.2.0/0.2.1 previews and the historical recovery release are drafts.
No 0.2.2 installer is publicly released. It remains ad-hoc signed and unnotarized;
Developer ID signing/notarization and explicit publication approval are required
before advertising trusted public distribution. An available source URL or
metadata screening is not item-specific rights clearance.

Immersive-detail thumbnail snapshot: `motion-site-572fbde5ca6b`, content/configuration SHA-256
`572fbde5ca6ba326c1097698d50ba69354dbe22f22f277db80e4eafa4f503948`.
Wallpaper previews now use the supplied Wallper-style artwork-backed detail
window, source metadata pills, centered title/description, and functional Library,
search, and share-link controls. Author/size/likes are cached source values, not
invented credits or live counts. Set as Wallpaper and video download remain
disabled browser controls; this is not animated native playback. Live acceptance
also checks Winter Forest, Japanese Village, Cat Pond, direct wallpaper links,
favorites, share links, and mobile scrolling. No native files or media approvals
changed with this detail-view rollout.
The app repository documents the exact approval schema in
`website/MEDIA-POLICY.md`, audit in `website/MEDIA-LICENSE-AUDIT.md`, and current
native checks in `docs/RELEASE-VALIDATION.md` and current website checks in
`docs/WEBSITE-TYPESCRIPT.md`. Live acceptance must confirm 353 image-only wallpapers,
Cat Pond first, no Aurora, empty video catalog/downloads, paused policy, 404 source
and old Aurora paths, and two ready replicas. Never roll back to the Aurora-only
snapshot when servicing this user-requested showcase.
