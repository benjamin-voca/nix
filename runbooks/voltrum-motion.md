# Voltrum Motion

Public website: https://motion.voltrum.co. The root Voltrum site is unchanged.
Application source: https://github.com/klajdi-g/Wapper. Public installers are
withdrawn pending rights review and production signing.

`modules/outputs/bootstrap/voltrum-motion.nix` adds
`apps/voltrum-motion/resources.json` to the declarative bootstrap output.
The Kubernetes List defines an isolated `voltrum-motion` namespace with a
content-addressed immutable ConfigMap, two non-root nginx replicas, service,
and ingress. The existing wildcard Cloudflare tunnel routes the hostname to
ingress-nginx; no tunnel or DNS replacement is needed.

Generate updates from the app repository with:

```sh
node website/validate.mjs
python3 tools/package-motion-site.py ../nix
```

Use authorized local kubectl credentials to dry-run and apply the generated
List, then verify the rollout and public manifests:

```sh
kubectl apply --dry-run=server -f apps/voltrum-motion/resources.json
kubectl apply -f apps/voltrum-motion/resources.json
kubectl -n voltrum-motion rollout status deployment/voltrum-motion
curl -f https://motion.voltrum.co/release.json
curl -f https://motion.voltrum.co/catalog.json
```

Commit the resulting resources alongside any bootstrap changes. Do not place
credentials, native installers, or downloaded videos in the ConfigMap. Previous
ConfigMaps should remain available while their ReplicaSets are needed. Rollback
is allowed only to a complete snapshot enforcing the current publication policy.
Never roll back to a pre-quarantine snapshot containing unreviewed media or
installer links. Do not use an arbitrary previous ReplicaSet for rollback.

The website has no backend, accounts, or application analytics. It reads catalog
and release manifests from the same origin. Its self-only script CSP also blocks
the Cloudflare-injected analytics beacon observed during browser checks.

As of October 29, 2026, the shared app-repository `website/media-policy.json` is
paused with `allowNativeDownloads: false` and `approvedMedia: []`. No real IDs are
approved. Public `catalog.json` is `[]` and `release.json` has no downloads.
The 159 source candidates are not cleared for publication. Paused CSP is
`media-src 'none'` and `img-src 'self'`. Keep this policy enforced in generated
resources; do not publish source candidate manifests directly.

Native 0.2.2 is a local-only demo/import build with zero bundled remote entries.
Earlier 0.2.0/0.2.1 previews and the historical recovery release are drafts.
No 0.2.2 installer is publicly released. It remains ad-hoc signed and unnotarized;
Developer ID signing/notarization and explicit publication approval are required
before advertising trusted public distribution. An available source URL or
metadata screening is not item-specific rights clearance.

Verified paused snapshot: `motion-site-c9ab4bdb8d56`, content/configuration SHA-256
`c9ab4bdb8d569663e5428fd34c1abd4cf7c4989e3a1ef3022990f68fec48c45e`.
The app repository documents the exact approval schema in
`website/MEDIA-POLICY.md`, audit in `website/MEDIA-LICENSE-AUDIT.md`, and current
native/browser checks in `docs/RELEASE-VALIDATION.md`.
