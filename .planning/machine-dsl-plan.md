# Plan: Machine Management DSL for QuadNix

## Context

QuadNix currently manages machines through:
- `modules/hosts/*.nix` — host definitions calling `mkClusterHost`
- `modules/roles/*.nix` — role compositions (imports profiles + services)
- `modules/profiles/*.nix` — reusable profile modules
- `modules/outputs/bootstrap.nix` — K8s manifests (completely decoupled from NixOS)
- Manual `deploy-rs` commands for deployment

**Problems:**
1. No single source of truth for machine state
2. K8s resources live separately from machine definitions
3. Diffing is ad-hoc (manual kubectl diff, no nix-level comparison)
4. Deployment requires multiple commands (build, kubectl apply, deploy-rs)
5. Adding a new host requires touching multiple files (hosts/, roles/, profiles/, secrets/)

**Goal:** A unified DSL that centralizes machine definitions, enables declarative diff/deploy, and reduces the steps to add a new machine.

---

## Design

### Central Registry: `machines/index.nix`

```
machines/
├── index.nix           # The DSL — machine registry, roles, profiles, k8s resources
├── lib/
│   ├── machine-diff.nix    # Diff two machine configs
│   ├── machine-deploy.nix  # Deployment helpers
│   └── k8s-composable.nix   # K8s resource builders
├── hosts/
│   ├── backbone-01.nix     # Hardware-specific config (can stay in modules/hardware/)
│   └── frontline-01.nix
└── roles/
    ├── backbone.nix         # Role implementations (can stay in modules/roles/)
    └── frontline.nix
```

### The DSL Interface

```nix
# machines/index.nix
{ lib, inputs }:

{
  # ── Machine Registry ──────────────────────────────────────────────
  machines = {
    backbone-01 = {
      system = "x86_64-linux";
      hardware = ./hardware/backbone-01.nix;
      role = roles.control-plane;
      taints = [
        { key = "role"; value = "backbone"; effect = "NoSchedule"; }
        { key = "infra"; value = "true"; effect = "NoSchedule"; }
      ];
      secrets = ./secrets/backbone-01.yaml;
    };

    frontline-01 = {
      system = "x86_64-linux";
      hardware = ./hardware/frontline-01.nix;
      role = roles.worker;
      taints = [
        { key = "role"; value = "frontline"; effect = "NoSchedule"; }
      ];
      secrets = ./secrets/frontline-01.yaml;
    };
  };

  # ── Role Definitions ──────────────────────────────────────────────
  roles = {
    control-plane = {
      profiles = [ profiles.base profiles.server profiles.kubernetes.control-plane ];
      extraModules = [
        ./services/argocd-deploy.nix
        ./services/helm-charts.nix
        # ...
      ];
    };

    worker = {
      profiles = [ profiles.base profiles.server profiles.kubernetes.worker ];
      extraModules = [
        ./services/cloudflared-host.nix  # Host-level cloudflared
      ];
    };
  };

  # ── Profile Library ───────────────────────────────────────────────
  profiles = {
    base = import ../modules/profiles/base.nix;
    server = import ../modules/profiles/server.nix;
    docker = import ../modules/profiles/docker.nix;
    kubernetes = {
      control-plane = import ../modules/profiles/kubernetes/control-plane.nix;
      worker = import ../modules/profiles/kubernetes/worker.nix;
    };
  };

  # ── K8s Resources (tied to cluster, not individual machines) ─────
  kubernetes = {
    cluster = "quadtech";  # Cluster name
    ingress = {
      class = "nginx";
      ip = "192.168.1.240";
    };

    namespaces = [
      { name = "orkestr"; }
      { name = "edukurs"; }
      { name = "harbor"; }
      { name = "argocd"; }
      # ...
    ];

    helm-releases = {
      argocd = { chart = "argo-cd"; values = {}; };
      harbor = { chart = "harbor"; values = {}; };
    };

    argocd-apps = {
      edukurs = { repo = "..."; path = "k8s"; namespace = "edukurs"; };
      # ...
    };
  };
}
```

---

## Implementation Phases

### Phase 1: Create Machine Registry Structure

**Goal:** Establish `machines/` directory with the DSL index and supporting lib.

**Tasks:**
1. Create `machines/` directory structure
2. Create `machines/index.nix` with the DSL schema
3. Create `machines/lib/machine-diff.nix` for config comparison
4. Create `machines/lib/machine-deploy.nix` for deployment helpers
5. Wire `machines/index.nix` into `flake.nix` outputs
6. Verify `nix build .#machines` produces valid output

**Deliverable:** A working (if incomplete) machine registry that can be queried.

---

### Phase 2: Migration — Move Existing Definitions

**Goal:** Transfer current `modules/hosts/`, `modules/roles/`, `modules/profiles/` into the new structure.

**Tasks:**
1. Map existing host definitions to `machines.machines` entries
2. Map existing roles to `machines.roles`
3. Map existing profiles to `machines.profiles`
4. Verify `flake.nix` outputs still produce `nixosConfigurations` for all hosts
5. Run `nix flake check` to validate
6. Test `deploy-rs --dry-activate .#backbone-01` still works

**Deliverable:** All current hosts represented in `machines/index.nix`, zero functional change.

---

### Phase 3: Integrate K8s Resources into DSL

**Goal:** Move K8s resources from `modules/outputs/bootstrap.nix` into the DSL, enabling unified diff/deploy.

**Tasks:**
1. Create `machines/lib/k8s-composable.nix` with resource builders:
   - `mkNamespace`
   - `mkHelmRelease`
   - `mkArgoApp`
   - `mkConfigMap`
   - `mkDeployment`
2. Refactor `modules/outputs/bootstrap.nix` to use `k8s-composable`
3. Add K8s resources to `machines/index.nix.kubernetes` section
4. Generate `result/k8s-manifests.yaml` from DSL
5. Verify `kubectl diff -f result/k8s-manifests.yaml` works

**Deliverable:** K8s resources generated from `machines/index.nix`, current manifests unchanged.

---

### Phase 4: Diff Implementation

**Goal:** Enable `nix run .#machines.diff -- --host backbone-01` to show config changes.

**Tasks:**
1. Extend `machine-diff.nix` with:
   - `buildManifest(host)` — evaluate host config to JSON
   - `diff(prev, next)` — compare two manifests, output human-readable diff
2. Add `flake.nix` output for `packages.machines-diff`
3. Create `scripts/machine-diff.sh` wrapper script
4. Add CI step to show diff on PRs

**Deliverable:** `machines diff backbone-01` shows what would change on that host.

---

### Phase 5: Unified Deploy Command

**Goal:** Single `machines deploy --host backbone-01` replaces multiple manual steps.

**Tasks:**
1. Create `machines/lib/machine-deploy.nix` with:
   - `deploy NixOS host` — wraps deploy-rs
   - `deployK8s manifests` — kubectl apply with diff preview
   - `deployAll` — deploys NixOS + K8s in correct order
2. Create `scripts/machine-deploy.sh`:
   ```bash
   # Dry-run (default)
   machines deploy --host backbone-01 --dry-run
   
   # Apply K8s changes
   machines deploy k8s --diff
   
   # Deploy NixOS config
   machines deploy nixos --host backbone-01
   
   # Full deploy
   machines deploy all --host backbone-01
   ```
3. Add pre-deploy hooks (secrets check, backup reminder)
4. Add post-deploy verification (kubectl get pods, deploy-rs status)

**Deliverable:** `machines deploy --help` shows unified CLI.

---

### Phase 6: CI/CD Integration

**Goal:** Push to `main` → CI builds → CD deploys automatically.

**Tasks:**
1. Create `.forgejo/workflows/machines.yaml`:
   ```yaml
   on:
     push:
       branches: [main]
   
   jobs:
     build:
       - name: Build machines
         run: nix build .#machines
   
     diff:
       - name: Show changes
         run: |
           machines diff --all --format github 2>&1 | head -50
   
     deploy-k8s:
       - name: Deploy K8s manifests
         run: kubectl apply -f result/k8s-manifests.yaml --server-side
         if: github.ref == 'main'
   
     deploy-nixos:
       - name: Deploy NixOS
         run: deploy-rs .#all --skip-checks
         if: github.ref == 'main'
   ```
2. Add PR workflow for diff-only (no deploy):
   ```yaml
   on:
     pull_request:
       branches: [main]
   
   jobs:
     diff:
       - name: Show what would change
         run: machines diff --all --format github
   ```
3. Add secrets injection step (sops-nix in CI)
4. Add changelog generation (git-cliff)

**Deliverable:** Full CI/CD pipeline for machine management.

---

### Phase 7: Simplify Adding New Machines

**Goal:** New machine requires only: hardware module, secrets file, one line in `machines/index.nix`.

**Tasks:**
1. Document the minimal steps:
   ```bash
   # 1. Create hardware module
   vim machines/hardware/my-new-host.nix
   
   # 2. Create secrets
   vim secrets/my-new-host.yaml
   
   # 3. Add to registry
   # In machines/index.nix:
   my-new-host = {
     system = "x86_64-linux";
     hardware = ./hardware/my-new-host.nix;
     role = roles.worker;
     secrets = ./secrets/my-new-host.yaml;
   };
   
   # 4. Test
   nix build .#nixosConfigurations.my-new-host.config.system.build.toplevel
   
   # 5. Deploy
   machines deploy nixos --host my-new-host
   ```
2. Add validation in DSL (check hardware exists, secrets exist, role exists)
3. Add `machines validate` command to catch errors early
4. Add `machines list` command to show all registered machines

**Deliverable:** "Add a machine in 3 files" guide.

---

## Technical Decisions

| Decision | Rationale |
|----------|-----------|
| Keep existing file structure | `modules/hosts/`, `modules/roles/`, `modules/profiles/` stay, referenced from `machines/index.nix` |
| K8s resources in DSL | Enables unified diff/deploy, single source of truth |
| NixOS configs still from `mkClusterHost` | Don't rewrite working abstraction |
| deploy-rs stays | Proven, well-integrated; wrap it, don't replace it |
| K8s manifests as YAML output | kubectl compatibility; generated from Nix |
| CLI wrapper scripts | UX layer, doesn't change underlying tools |

---

## File Changes Summary

| File | Action |
|------|--------|
| `machines/index.nix` | **NEW** — central DSL registry |
| `machines/lib/machine-diff.nix` | **NEW** — config diffing |
| `machines/lib/machine-deploy.nix` | **NEW** — deployment helpers |
| `machines/lib/k8s-composable.nix` | **NEW** — K8s resource builders |
| `machines/scripts/machine-diff.sh` | **NEW** — diff CLI |
| `machines/scripts/machine-deploy.sh` | **NEW** — deploy CLI |
| `flake.nix` | **MODIFY** — add `machines` output |
| `modules/outputs/bootstrap.nix` | **MODIFY** — refactor to use k8s-composable |
| `.forgejo/workflows/machines.yaml` | **NEW** — CI/CD pipeline |
| `AGENTS.md` | **UPDATE** — add machines/ commands |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking existing deploys | Phase 2 validates no functional change before proceeding |
| K8s manifest generation breaks | Generate to temp, compare with current before replacing |
| Complexity increase | Start with minimal DSL, add features only when needed |
| CI/CD too aggressive | PR workflow only shows diff, no deploy; main requires manual approve |

---

## Success Criteria

- [ ] `machines/index.nix` contains all host definitions
- [ ] `nix build .#machines` produces K8s manifests identical to current bootstrap
- [ ] `machines diff backbone-01` shows actionable diff between current and previous
- [ ] `machines deploy nixos --host backbone-01` works identically to current deploy-rs
- [ ] `machines deploy k8s --diff` shows K8s changes before applying
- [ ] Adding a new host requires ≤3 files (hardware, secrets, registry entry)
- [ ] CI/CD deploys on `main` push without manual intervention
- [ ] Zero regression in existing deploys (backbone-01, frontline-01)