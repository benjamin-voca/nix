# ZERO38 — https://z38.voltrum.co

The latest built React frontend from `Developer/GitHub/Zero38Tattoos/dist` is snapshotted in
`resources.json`. Testing-ground files are not published. The manifest includes
the namespace, compressed site ConfigMaps, nginx configuration, two-replica
Deployment, Service and Ingress. No runtime downloads or mutable host files.

The snapshot comes from `QuadCoreTech/Zero38Tattoos`, including the persistent
full-recording YouTube player, availability calendar, restored copy, and Voltrum
footer credit. The music player has no 30-second playback limit.

This client-review deployment uses `bun run build:preview`. Share
`https://z38.voltrum.co/admin?preview=1` to inspect the sample dashboard on any device
without a password. It only uses fictional records, with settings saved locally
in the visitor's browser. It does not authenticate to the real admin backend.
Use the normal `bun run build` when replacing this review with the operational site.

Cloudflare's existing wildcard DNS and tunnel route cover `z38.voltrum.co`;
the ingress terminates the route in namespace `z38`. Public HTTPS is provided
by Cloudflare. nginx preserves the new app's Netlify security headers, SPA
routing, and legacy URL redirects. Private-page entry points retain noindex and
no-store (not authentication).

nginx uses relative redirects (`absolute_redirect off`) so legacy links retain
the public HTTPS origin instead of exposing the internal HTTP port 8080.

## Backend status

This is a **frontend-only deployment**. `/api/*` and `/.netlify/functions/*`
explicitly return JSON HTTP 503 instead of pretending booking requests succeed.
The new source uses Netlify Functions, Neon PostgreSQL, and Resend. No configured
site or server credentials were present in the checkout. Before enabling booking,
deploy the API and scheduled worker, configure the secrets documented in the app's
README (`SITE_URL=https://z38.voltrum.co`), review/apply the database migrations,
and verify authentication, booking, consent encryption, and email end-to-end.
No production database migrations or data imports were performed.

To publish a newly approved live copy:

```sh
cd /path/to/Zero38Tattoos
bun run build:preview
cd /path/to/nix
python3 apps/z38/generate.py '/path/to/Zero38Tattoos/dist'
kubectl apply --server-side -f apps/z38/resources.json
kubectl -n z38 rollout status deployment/z38 --timeout=180s
```

Review and commit the regenerated snapshot. The same resources are included
in the Nix bootstrap output as `29-z38.yaml`. Site/config checksums trigger a
rolling update whenever the snapshot changes. Each archive chunk is kept below
the ConfigMap size limit. For larger sites, migrate assets to object storage
or a cluster-built image instead of expanding ConfigMap storage indefinitely.
