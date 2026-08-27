# ClickStack (HyperDX) — Runbook

Self-hosted observability for logs (traces later), replacing the broken
Loki/Tempo path. Primary consumer today: **Roblox experience debugging**
via `apps/roblox-otel/`.

## Architecture (single-node, no operators)

```
roblox experience ──HttpService──► otlp.voltrum.co ──cloudflared/nginx──┐
cluster pods (later) ──────────────► collector :4318                    │
                                                                        ▼
   HyperDX UI (hyperdx.voltrum.co) ◄── clickstack-hyperdx deploy
   MongoDB (mongo:5.0, app state)            │ queries
   ClickHouse 25.7 (otel_* tables) ◄─────────┘ + clickstack-otel-collector
```

Upstream chart `clickstack 3.2.0` is used in **minimal mode**: only the
HyperDX deployment renders; ClickHouse, MongoDB and the OTel collector are
plain Nix-rendered workloads (`modules/outputs/bootstrap/clickstack.nix`).
No ClickHouse/Mongo operators, no cert-manager dependency, no CRD ordering
races — deliberate for the single-node cluster.

| Piece | Where | Notes |
|---|---|---|
| Chart def | `lib/helm/charts/clickstack.nix` | pinned 3.2.0, `hyperdx.secrets=null` |
| Bootstrap module | `modules/outputs/bootstrap/clickstack.nix` | ns 13a..13g, chart 13z |
| Secrets | sops `secrets/backbone-01.yaml` keys `clickstack-*` | see `machines/default.nix` requiredSecrets |
| Secret injection | `modules/services/k8s-secrets-inject.nix` | creates `clickstack-secrets` + `clickstack-clickhouse-users` |
| Users | CH `app` (UI), `otelcollector` (ingest) | sha256 hashes in users.d secret, hot-reloaded |
| Roblox SDK | `apps/roblox-otel/` | OTLP JSON logs + client relay |

## Deploy

```sh
nix build .#bootstrap   # or via deploy-rs flow
kubectl apply -f result/13a-clickstack-namespace.yaml
kubectl apply -f result/13b-*.yaml -f result/13c-*.yaml -f result/13d-*.yaml \
              -f result/13e-*.yaml -f result/13f-*.yaml -f result/13g-*.yaml
kubectl apply -f result/13z-clickstack-chart.yaml
# secrets: restart k8s-secrets-inject on backbone-01 if not yet run
ssh backbone01 systemctl restart k8s-secrets-inject
```

First-boot ordering: pods may CrashLoop until
`k8s-secrets-inject` creates `clickstack-secrets` (they self-heal).

## Verify

```sh
kubectl -n clickstack get pods
kubectl -n clickstack logs deploy/clickstack-otel-collector --tail=20   # schema init
OTLP_TOKEN=$(sops -d secrets/backbone-01.yaml | grep clickstack-otlp-token | cut -d' ' -f2) \
  ./apps/roblox-otel/test-otlp.sh                                       # → 200
```

Then open `https://hyperdx.voltrum.co`, create the admin user, check the
auto-seeded sources (Local ClickHouse → Logs/Traces/Metrics), search
`service.name: otlp-smoketest`.

## URLs

- UI: `hyperdx.voltrum.co` (Cloudflare wildcard → nginx ingress)
- Ingest: `otlp.voltrum.co/v1/logs` (+ `/v1/traces`, `/v1/metrics` ready)

## Ops notes

- **Retention:** ClickStack TTL default is 3 days. Change later via
  `ALTER TABLE otel_logs MODIFY TTL Timestamp + toIntervalDay(14)` etc. on
  `otel_logs`, `otel_traces`, `otel_metrics_*`, `otel_metrics_exp_hist_*`.
- **Rotate token:** `sops --set '["clickstack-otlp-token"] "new"' secrets/backbone-01.yaml`,
  redeploy, re-inject (injector sets both `OTLP_AUTH_TOKEN` and
  `HYPERDX_API_KEY`; UI API key page shows the same value).
- **Rotate CH passwords:** new sops value → re-inject → restart the CH sts
  (users.d hot-reload picks the file change; restart if unsure) → HyperDX
  picks up env on next restart.
- **Scale CH:** statefulset PVC is ceph-block, expandable; bump CPU limits
  first (requests stay low — the node's CPU requests are already ~85%).
- **Upgrades:** bump `version` in `lib/helm/charts/clickstack.nix` (chart)
  + image tags for CH/collector in the bootstrap module; `nix build
  .#bootstrap`; apply. HyperDX minor bumps are usually safe; read the chart
  changelog for schema migrations.
- **Uninstall:** reverse order — 13z chart, 13g..13a, then PVCs
  (mongo-data, clickhouse data) are kept for data safety.

## Deliberate omissions

- Sessions/session-replay source (add later; needs the HyperDX session
  receiver endpoint enabled).
- DORA/prometheus integration (kube-prometheus-stack grafana still up and
  can read ClickHouse via the plugin if ever needed).

## Deployed-state deltas (2026-08-27)

Decisions locked during first deploy — do not regress:

- **Collector runs standalone** (`OPAMP_SERVER_URL=""` env override in
  13f). Supervisor/OpAMP mode crashes during remote-config application in
  this topology. Standalone config reads `CLICKHOUSE_*` + `OTLP_AUTH_TOKEN`
  envs, health_check on 13133.
- **Auth scheme is RAW token**: bearertokenauth ships `scheme: ""` — the
  `Authorization` header must be exactly `clickstack-otlp-token`, NOT
  `Bearer <token>`. Roblox SDK + test-otlp.sh follow this.
- **CH entrypoint**: `CLICKHOUSE_SKIP_USER_SETUP=1` (users.d is a read-only
  secret mount); `default` user lockdown ships as `default-user.xml` in the
  managed secret.
- **Cloudflare DNS**: tunnel ingress has a `*` route but voltrum.co has
  per-host CNAMEs only. `otlp` / `hyperdx` CNAMEs must be added to the
  voltrum.co zone pointing at the tunnel (`<tunnel-id>.cfargotunnel.com`)
  before public URLs resolve.

## DNS (2026-08-27)

`*.voltrum.co` CNAME → `b6bac523-be70-4625-8b67-fa78a9e1c7a5.cfargotunnel.com`
(proxied) created via Cloudflare API (record id b8e9687f9d77b6c4f090be1fcea88bf6).
Explicit records (www → Pages, mosaic, f1 → old frontline tunnel, mail/TXT)
always win over the wildcard — nothing was swallowed. `otlp` / `hyperdx` /
any future service hostname now resolve with zero DNS work.
