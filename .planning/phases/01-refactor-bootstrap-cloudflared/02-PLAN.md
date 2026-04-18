---
wave: 2
depends_on: [01]
files_modified:
  - modules/outputs/bootstrap.nix (deleted/replaced)
  - modules/outputs/bootstrap/default.nix (new)
  - modules/outputs/bootstrap/metallb.nix (new)
  - modules/outputs/bootstrap/ingress.nix (new)
  - modules/outputs/bootstrap/argocd.nix (new)
  - modules/outputs/bootstrap/rook-ceph.nix (new)
  - modules/outputs/bootstrap/cnpg.nix (new)
  - modules/outputs/bootstrap/forgejo.nix (new)
  - modules/outputs/bootstrap/cloudflared.nix (new)
  - modules/outputs/bootstrap/harbor.nix (new)
  - modules/outputs/bootstrap/monitoring.nix (new)
  - modules/outputs/bootstrap/minecraft.nix (new)
  - modules/outputs/bootstrap/verdaccio.nix (new)
  - modules/outputs/bootstrap/apps.nix (new)
  - modules/outputs/bootstrap/erpnext.nix (new)
autonomous: true
---

# Plan 02: Split bootstrap.nix into Modular Sub-Files

## Objective
Replace the monolithic `modules/outputs/bootstrap.nix` (~600 lines) with a directory of focused sub-modules under `modules/outputs/bootstrap/`. Each sub-module handles one service/app. The `default.nix` orchestrator composes them all.

## Context
The existing `openclaw.nix` in `modules/outputs/bootstrap/` already demonstrates the pattern: each module takes `{ lib, pkgs, ... }` and returns `{ manifests = { "<name>.yaml" = derivation; }; }`. The existing `render.nix` provides `writeOne` and `writeMany` helpers.

## Strategy
This is a large mechanical extraction. Each sub-module is extracted from the corresponding section of `bootstrap.nix`. The logic is identical — only the packaging changes.

### Task 1: Delete `modules/outputs/bootstrap.nix` and create `modules/outputs/bootstrap/default.nix`

<read_first>
- modules/outputs/bootstrap.nix (the full 600-line monolith — source for ALL extractions)
- modules/outputs/bootstrap/openclaw.nix (pattern reference for return type)
- modules/outputs/bootstrap/render.nix (existing render utilities)
- modules/shared/cloudflared-routes.nix (from Plan 01 — cloudflared config source)
</read_first>

<action>
**Delete** `modules/outputs/bootstrap.nix`.

**Create** `modules/outputs/bootstrap/default.nix` as the new orchestrator. It should:

1. Accept `{ config, lib, inputs, ... }` (same signature as the old bootstrap.nix)
2. Keep the `let ... in` block with `systems`, `forAllSystems`, `pkgsFor`, `helmLibFor`, `chartsFor`, `composableFor` (these are shared infrastructure)
3. Define `bootstrapFor = system:` which:
   a. Sets up the same local bindings (`pkgs`, `charts`, `helmLib`, `kubelib`, `composable`, `existingCharts`, `openclawBootstrap`)
   b. Imports each sub-module, passing the required args
   c. Merges all manifests into a single attrset
   d. Uses the same `runCommand "bootstrap-manifests"` approach to write all files and combine into `bootstrap.yaml`

4. The final `runCommand` script should:
   - Write each sub-module's manifests to `$out/`
   - Combine all into `$out/bootstrap.yaml` in the same order as the original
   - Include the Python post-processing steps (strip CRD annotations, fix forgejo service targetPort, fix forgejo-actions serviceName) — these go into the orchestrator since they're cross-cutting patches

5. Output: `config.flake.bootstrap = forAllSystems bootstrapFor;`

The `default.nix` should be under 150 lines. All manifest content lives in the sub-modules.
</action>

<acceptance_criteria>
- `modules/outputs/bootstrap.nix` no longer exists
- `modules/outputs/bootstrap/default.nix` exists and is under 150 lines
- `default.nix` imports all sub-modules and merges their `manifests` attrsets
- `default.nix` preserves the Python post-processing for CRD annotation stripping, forgejo service targetPort, and forgejo-actions serviceName
- `default.nix` preserves the final `bootstrap.yaml` concatenation in the same file order
- Output `config.flake.bootstrap` has the same type as before (`forAllSystems bootstrapFor`)
</acceptance_criteria>

### Task 2: Create `modules/outputs/bootstrap/metallb.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing metallbChart, metallbIPAddressPool)
</read_first>

<action>
Extract from `bootstrap.nix`:
- `metallbChart` — the `kubelib.buildHelmChart` call for MetalLB
- `metallbIPAddressPool` — the inline YAML for IPAddressPool and L2Advertisement CRDs

Return `{ manifests = { "00-metallb.yaml" = metallbChart; "00-metallb-crds.yaml" = renderedCRDs; }; }`

The function signature: `{ pkgs, lib, charts, kubelib }:`

Use `render.writeOne` for the CRDs (convert the inline YAML string to a derivation).
</action>

<acceptance_criteria>
- `modules/outputs/bootstrap/metallb.nix` exists
- Returns `{ manifests = { ... }; }` with keys `"00-metallb.yaml"` and `"00-metallb-crds.yaml"`
- Metallb chart uses same values (controller/speaker resources) as original
- IPAddressPool range is `192.168.1.240-192.168.1.250`
- L2Advertisement references `default` pool
</acceptance_criteria>

### Task 3: Create `modules/outputs/bootstrap/ingress.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing ingressNginxChart)
</read_first>

<action>
Extract `ingressNginxChart` — the `kubelib.buildHelmChart` call for ingress-nginx.

Signature: `{ pkgs, lib, charts, kubelib }:`

Return `{ manifests = { "01-ingress-nginx.yaml" = ingressNginxChart; }; }`
</action>

<acceptance_criteria>
- File exists, returns `{ manifests."01-ingress-nginx.yaml" = ...; }`
- Chart uses `service.type = "LoadBalancer"`
</acceptance_criteria>

### Task 4: Create `modules/outputs/bootstrap/argocd.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing argocdChart, argocd namespace)
</read_first>

<action>
Extract:
- ArgoCD namespace YAML (`01a-argocd-namespace.yaml`)
- `argocdChart` — the `kubelib.buildHelmChart` call (`01b-argocd.yaml`)

Signature: `{ pkgs, lib, charts, kubelib, render }:`

Return manifests with keys `"01a-argocd-namespace.yaml"` and `"01b-argocd.yaml"`.

The ArgoCD namespace uses `render.writeOne` with the same attrset as original.
</action>

<acceptance_criteria>
- File returns manifests with both namespace and chart
- ArgoCD values match original (domain, insecure, image tag v2.9.3, etc.)
</acceptance_criteria>

### Task 5: Create `modules/outputs/bootstrap/rook-ceph.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing rookCephChart, rookCephClusterChart, rook-ceph namespace, RGW user, RGW bucket job)
</read_first>

<action>
Extract:
- `rookCephChart` from `existingCharts."rook-ceph"` (`02-rook-ceph.yaml`)
- `rookCephClusterChart` from `existingCharts."rook-ceph-cluster"` (`03-rook-ceph-cluster.yaml`)
- Rook-Ceph namespace (`02d-rook-ceph-namespace.yaml`)
- Ceph RGW CNPG user (`02e-ceph-rgw-cnpg-user.yaml`)
- Ceph RGW CNPG bucket job (`02f-ceph-rgw-cnpg-bucket-job.yaml`)
- EduKurs CNPG scheduled backup (`02g-edukurs-cnpg-scheduled-backup.yaml`)
- Forgejo CNPG scheduled backup (`02h-forgejo-cnpg-scheduled-backup.yaml`)
- Forgejo namespace (`02i-forgejo-namespace.yaml`)

Signature: `{ pkgs, lib, existingCharts, render }:`

Return all as individual manifest entries.
</action>

<acceptance_criteria>
- File returns manifests with all 8 items listed above
- RGW user name is `cnpg-backups`, store `ceph-objectstore`
- Bucket job uses `amazon/aws-cli:2.17.40` image
- Backup schedules match original (`0 0 * * * *` and `0 15 * * * *`)
</acceptance_criteria>

### Task 6: Create `modules/outputs/bootstrap/cnpg.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing CNPG operator chart, cluster, namespace, databases)
</read_first>

<action>
Extract:
- CNPG operator chart from `existingCharts.cloudnative-pg` (`02a-cnpg-operator.yaml`)
- CNPG cluster manifest (`02b-cnpg-cluster.yaml`) — includes Cluster, shared-pg-app Secret, batllavatourist Database, quadpacienti Database
- CNPG namespace (`02c-cnpg-namespace.yaml`)
- EduKurs namespace (`15-edukurs-namespace.yaml`)
- BatllavaTourist namespace (`15-batllavatourist-namespace.yaml`)
- QuadPacienti namespace (`15-quadpacienti-namespace.yaml`)

Signature: `{ pkgs, lib, existingCharts, render }:`

Return all as individual manifest entries.
</action>

<acceptance_criteria>
- File returns manifests for operator, cluster, namespace, and all 3 app namespaces
- CNPG cluster uses `storageClass: ceph-block`, `size: 10Gi`, `instances: 1`
- Cluster bootstrap creates `edukurs` database
- batllavatourist and quadpacienti Database CRDs reference `shared-pg` cluster
</acceptance_criteria>

### Task 7: Create `modules/outputs/bootstrap/forgejo.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing forgejo chart, PVCs, runner, ArgoCD repo)
</read_first>

<action>
Extract:
- Forgejo chart from `existingCharts.forgejo` (`03-forgejo.yaml`)
- Forgejo shared storage Ceph PVC (`03a-forgejo-shared-storage-ceph-pvc.yaml`)
- Forgejo DB storageclass patch (`03b-forgejo-db-storageclass-patch.yaml`)
- Forgejo runner token secret (`04-forgejo-runner-secret.yaml`)
- Forgejo actions chart from `existingCharts.forgejo-actions` (`04-forgejo-actions.yaml`) — if not empty
- ArgoCD Forgejo repo CR (`04-argocd-forgejo-repo.yaml`)

Signature: `{ pkgs, lib, existingCharts, render }:`

Return all as manifest entries. Note: the forgejo-actions chart may be empty (check with `if [ ! -s ... ]` — the orchestrator should handle the optional case).
</action>

<acceptance_criteria>
- File returns manifests for forgejo chart, PVCs, DB patch, runner secret, actions chart, and ArgoCD repo
- Forgejo shared storage uses `ceph-filesystem-csi`, `ReadWriteMany`, `50Gi`
- Runner secret token is `RUNNER_TOKEN_PLACEHOLDER`
- ArgoCD repo URL is `https://forge.quadtech.dev/QuadCoreTech`
</acceptance_criteria>

### Task 8: Create `modules/outputs/bootstrap/cloudflared.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing cloudflaredConfigContent, cloudflared manifest, namespace, configmap, deployment)
- modules/shared/cloudflared-routes.nix (shared options from Plan 01)
</read_first>

<action>
Extract the K8s cloudflared resources, but **generate the config from `config.quad.cloudflared.*`** instead of the old hardcoded `cloudflaredConfigContent`.

Manifests:
- Cloudflared namespace (`05-cloudflared-namespace.yaml`)
- Cloudflared configmap (`05-cloudflared-configmap.yaml`) — data.config.yaml = `config.quad.cloudflared.configYaml` with metricsPort set to `config.quad.cloudflared.metricsPort` (2002 for K8s instance)
- Cloudflared deployment (`06-cloudflared-deployment.yaml`)

Signature: `{ pkgs, lib, config, render }:`

The deployment uses `hostNetwork: true`, image `cloudflare/cloudflared:latest`, same volume mounts as original.

**CRITICAL FIX**: The configmap's config.yaml MUST use `http://127.0.0.1:${toString config.quad.cloudflared.nodePort}` for all HTTP routes (port 30856), NOT port 80. This fixes the known bug from MEMORY.md.
</action>

<acceptance_criteria>
- File returns manifests for namespace, configmap, and deployment
- ConfigMap data contains the full cloudflared config derived from `config.quad.cloudflared.*`
- ALL HTTP service routes use `http://127.0.0.1:30856` (via `config.quad.cloudflared.nodePort`), NOT port 80
- SSH route uses `ssh://localhost:22`
- Deployment uses `hostNetwork: true`, same container spec as original
- Metrics port in config is `0.0.0.0:2002` (not 2003 — host uses 2003)
</acceptance_criteria>

### Task 9: Create `modules/outputs/bootstrap/harbor.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing harborChart, namespace, PVCs, ingress)
</read_first>

<action>
Extract:
- Harbor namespace (`09-harbor-namespace.yaml`)
- Harbor Ceph PVCs (`09a-harbor-pvcs-ceph.yaml`) — 5 PVCs: registry(100Gi), jobservice(1Gi), database(1Gi), redis(1Gi), trivy(5Gi)
- Harbor chart from `existingCharts.harbor` (`11-harbor-chart.yaml`)
- Harbor custom ingress (`12-harbor-ingress.yaml`)

Signature: `{ pkgs, lib, existingCharts, render }:`

Return all as manifest entries.
</action>

<acceptance_criteria>
- File returns manifests for namespace, PVCs, chart, and ingress
- Ingress has paths for `/api/`, `/service/`, `/v2/`, `/c/` (harbor-core) and `/` (harbor-portal)
- All PVCs use `ceph-block` storageClass
</acceptance_criteria>

### Task 10: Create `modules/outputs/bootstrap/monitoring.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing monitoringChart, monitoring namespace)
</read_first>

<action>
Extract:
- Monitoring namespace (`11-monitoring-namespace.yaml`)
- Prometheus chart from `existingCharts.prometheus` (`12-monitoring-chart.yaml`)

Signature: `{ pkgs, lib, existingCharts, render }:`

Return both as manifest entries.
</action>

<acceptance_criteria>
- File returns namespace and chart manifests
- Namespace is `monitoring`
</acceptance_criteria>

### Task 11: Create `modules/outputs/bootstrap/minecraft.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing minecraft namespace, ArgoCD app)
</read_first>

<action>
Extract:
- Minecraft namespace (`11-minecraft-namespace.yaml`)
- Minecraft ArgoCD Application (`14-minecraft-argocd-app.yaml`)

Signature: `{ pkgs, lib, render }:`

Return both as manifest entries.
</action>

<acceptance_criteria>
- File returns namespace and ArgoCD app manifests
- ArgoCD app uses chart `minecraft` from `https://itzg.github.io/minecraft-server-charts`, version `5.1.1`
- LoadBalancerIP is `192.168.1.245`
- Storage class is `ceph-block`, size `20Gi`
</acceptance_criteria>

### Task 12: Create `modules/outputs/bootstrap/verdaccio.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing verdaccio namespace, PVC, ArgoCD app)
</read_first>

<action>
Extract:
- Verdaccio namespace (`10-verdaccio-namespace.yaml`)
- Verdaccio PVC (`10a-verdaccio-pvc.yaml`) — `ceph-block`, `10Gi`
- Verdaccio ArgoCD Application (`13-verdaccio-argocd-app.yaml`)

Signature: `{ pkgs, lib, render }:`

Return all as manifest entries.
</action>

<acceptance_criteria>
- File returns namespace, PVC, and ArgoCD app
- ArgoCD app uses chart `verdaccio` version `4.29.0` from `https://charts.verdaccio.org`
- PVC uses existingClaim `verdaccio-data`
</acceptance_criteria>

### Task 13: Create `modules/outputs/bootstrap/apps.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing EduKurs, BatllavaTourist, QuadPacienti ArgoCD apps)
</read_first>

<action>
Extract:
- EduKurs ArgoCD Application (`16-edukurs-argocd-app.yaml`)
- BatllavaTourist ArgoCD Application (`16-batllavatourist-argocd-app.yaml`)
- QuadPacienti ArgoCD Application (`16-quadpacienti-argocd-app.yaml`)

Signature: `{ pkgs, lib, render }:`

Return all as manifest entries.
</action>

<acceptance_criteria>
- File returns 3 ArgoCD app manifests
- Each app has `automated.prune = true`, `selfHeal = true`
- EduKurs repoURL is `https://forge.quadtech.dev/QuadCoreTech/edukurs.git`
- All apps reference `path: k8s`, `targetRevision: main`
</acceptance_criteria>

### Task 14: Create `modules/outputs/bootstrap/erpnext.nix`

<read_first>
- modules/outputs/bootstrap.nix (lines containing ERPNext namespace, helpdesk redirect ingress)
</read_first>

<action>
Extract:
- ERPNext namespace (`12aa-erpnext-namespace.yaml`)
- ERPNext helpdesk redirect ingress (`12a-erpnext-helpdesk-redirect-ingress.yaml`)

Signature: `{ pkgs, lib, render }:`

Return both as manifest entries.
</action>

<acceptance_criteria>
- File returns namespace and ingress manifests
- Ingress has permanent-redirect annotation to `/desk/helpdesk` with code 308
- Ingress is for host `helpdesk.quadtech.dev`
</acceptance_criteria>

## Verification
1. `nix build .#bootstrap` succeeds without error
2. The output `result/bootstrap.yaml` is syntactically valid YAML
3. Each sub-module file exists and is individually readable
4. The `default.nix` orchestrator is under 150 lines
