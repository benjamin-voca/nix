# Phase 1: Refactor Bootstrap & Cloudflared

## Objective
Break `modules/outputs/bootstrap.nix` (~600 lines) into modular, composable files under `modules/outputs/bootstrap/`. Deduplicate cloudflared config into a single shared source of truth. Fix K8s cloudflared routing bug.

## Current Problems

1. **`bootstrap.nix` is a monolith**: ~600 lines of inline YAML manifests, helm chart config, Python scripts, and bash. Impossible to navigate or modify safely.
2. **Cloudflared config duplicated**: Routes are hardcoded in TWO places:
   - `modules/roles/backbone.nix` — host systemd cloudflared (correct: routes to `127.0.0.1:30856`)
   - `modules/outputs/bootstrap.nix` — K8s cloudflared deployment (WRONG: some routes use `127.0.0.1:80`)
3. **Routes disagree**: Per MEMORY.md, the K8s instance routes to `127.0.0.1:80` instead of `127.0.0.1:30856`. Cloudflare load-balances between both instances → random 404s.

## Plan

### Step 1: Extract shared cloudflared route config

**Create**: `modules/shared/cloudflared-routes.nix`

A Nix module that exposes `config.quad.cloudflared.ingressRules` — a single list of `{ hostname, service }` entries. Both the host systemd service and K8s deployment consume this same list.

```nix
# modules/shared/cloudflared-routes.nix
{ lib, ... }:
{
  options.quad.cloudflared = {
    tunnelId = lib.mkOption { type = lib.types.str; };
    metricsPort = lib.mkOption { type = lib.types.int; default = 2002; };
    ingressRules = lib.mkOption {
      type = lib.types.listOf (lib.types.attrs);
      description = "Shared cloudflared ingress rules (single source of truth)";
    };
    nodePort = lib.mkOption {
      type = lib.types.int;
      default = 30856;
      description = "NodePort for ingress-nginx (used by cloudflared)";
    };
  };
}
```

The actual route list goes in `backbone.nix` (or a dedicated config module):
```nix
config.quad.cloudflared.ingressRules = [
  { hostname = "forge.quadtech.dev"; service = "http://127.0.0.1:${nodePort}"; }
  { hostname = "argocd.quadtech.dev"; service = "http://127.0.0.1:${nodePort}"; }
  # ... etc
];
```

### Step 2: Refactor host cloudflared (backbone.nix)

Replace the hardcoded `cat > config.yaml << EOF` block in `backbone.nix` with a template that reads from `config.quad.cloudflared.ingressRules`. This eliminates the inline YAML.

The host systemd service stays in `backbone.nix` (it's host-specific), but it consumes the shared route list.

### Step 3: Split bootstrap.nix into modular files

**Current structure** (`modules/outputs/bootstrap.nix`):
One giant function that builds everything.

**Target structure** (`modules/outputs/bootstrap/`):
```
modules/outputs/bootstrap/
├── default.nix          # Main entry: composes all sub-modules, <100 lines
├── render.nix           # The runCommand that combines outputs into bootstrap.yaml (already exists!)
├── metallb.nix          # MetalLB chart + CRDs
├── ingress.nix          # Ingress-nginx chart
├── argocd.nix           # ArgoCD namespace + chart
├── rook-ceph.nix        # Rook operator + cluster + namespace + RGW
├── cnpg.nix             # CNPG operator + cluster + namespaces + backups
├── forgejo.nix          # Forgejo chart + PVCs + runner
├── cloudflared.nix      # Cloudflared namespace + configmap + deployment (reads from shared routes)
├── harbor.nix           # Harbor namespace + chart + PVCs + ingress
├── monitoring.nix       # Monitoring namespace + Prometheus chart
├── minecraft.nix        # Minecraft namespace + ArgoCD app
├── verdaccio.nix        # Verdaccio namespace + PVC + ArgoCD app
├── apps.nix             # EduKurs, BatllavaTourist, QuadPacienti namespaces + ArgoCD apps
├── openclaw.nix         # OpenClaw (already modular!)
└── erpnext.nix          # ERPNext namespace + ingress
```

Each sub-module:
- Takes `{ pkgs, lib, charts, helmLib, kubelib, composable, existingCharts, config }` as args
- Returns an attrset of `{ "<name>.yaml" = derivation; }`
- The `render.nix` (already exists!) combines them into the final `bootstrap.yaml`

The `default.nix` orchestrates:
```nix
let
  metallb = import ./metallb.nix { inherit pkgs lib charts kubelib; };
  ingress = import ./ingress.nix { inherit pkgs lib charts kubelib; };
  cloudflared = import ./cloudflared.nix { inherit pkgs lib config; };
  # ...
in
# Merge all manifests and pass to render.nix
```

### Step 4: Fix K8s cloudflared routing

In the new `cloudflared.nix`, ensure all routes point to `http://127.0.0.1:${config.quad.cloudflared.nodePort}` (i.e., 30856). This fixes the bug where the K8s deployment used port 80.

### Step 5: Update `imports.nix`

Add `modules/shared/` to the import list so the new `cloudflared-routes.nix` is picked up.

### Step 6: Verify

- `nix build .#bootstrap` produces identical output (same manifests, same order)
- Both cloudflared configs (host + K8s) have identical route lists
- `nix flake check` passes

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Bootstrap output changes subtly | Build before/after and diff the YAML |
| Cloudflared routes break during refactor | Deploy to backbone-01 first, verify tunnel connectivity |
| Import cycle with shared module | `cloudflared-routes.nix` is options-only, no imports of its own |

## Files Changed

| File | Action |
|------|--------|
| `modules/outputs/bootstrap.nix` | **Replace** with thin `default.nix` delegating to sub-modules |
| `modules/outputs/bootstrap/default.nix` | **Create** — new orchestrator |
| `modules/outputs/bootstrap/metallb.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/ingress.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/argocd.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/rook-ceph.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/cnpg.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/forgejo.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/cloudflared.nix` | **Create** — extract + fix routes |
| `modules/outputs/bootstrap/harbor.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/monitoring.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/minecraft.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/verdaccio.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/apps.nix` | **Create** — extract from bootstrap.nix |
| `modules/outputs/bootstrap/erpnext.nix` | **Create** — extract from bootstrap.nix |
| `modules/shared/cloudflared-routes.nix` | **Create** — shared route config options |
| `modules/roles/backbone.nix` | **Modify** — consume shared cloudflared routes |
| `modules/imports.nix` | **Modify** — add `shared/` directory |

## Estimated Complexity
**Medium-High** — large mechanical extraction, but the logic stays the same. The main risk is ensuring the combined bootstrap.yaml is byte-identical.
