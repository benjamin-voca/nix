# Voltrum Motion

Public website: https://motion.voltrum.co. The root Voltrum site is unchanged.
Application source and preview installers: https://github.com/klajdi-g/Wapper.

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
ConfigMaps should remain available while old ReplicaSets can be rolled back.
For durable rollback, reapply the previous committed resources JSON.

The website has no backend, accounts, or analytics. It reads catalog and release
manifests locally and embeds optional credited NASA previews directly. Native
video files are downloaded on user confirmation in the macOS application.

Version 0.2.0 is an ad-hoc signed, unnotarized macOS preview. Do not advertise
Apple-trusted distribution until Developer ID signing/notarization completes.
Release status and hashes originate in the app's generated `release.json`.
