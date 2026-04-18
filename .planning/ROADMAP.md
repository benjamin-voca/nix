# QuadNix Roadmap

## Vision

Refactor the QuadNix NixOS configuration repo for malleability and extensibility, add a real second host (frontline-01), and establish true GitOps CI/CD so that a push to `main` automatically builds, tests, and deploys everything.

---

## Current State

- **1 real host**: backbone-01 (control-plane, runs everything)
- **3 stub hosts**: backbone-02, frontline-01, frontline-02 (hardware placeholders)
- **600-line `bootstrap.nix`**: all K8s manifests inline, impossible to navigate
- **Duplicated cloudflared config**: host systemd + K8s deployment, routes disagree
- **All secrets in one file**: `secrets/backbone-01.yaml`
- **Hardcoded master address**: worker profile assumes `backbone-01.local`
- **Existing CI**: Forgejo Actions pipeline (format check, flake check, build, helm publish, deploy backbone-01) — but no bootstrap automation, no multi-host deploy, no git-cliff tagging

---

## Phases

| Phase | Name                              | Status   | Depends On | Plans |
| ----- | --------------------------------- | -------- | ---------- | ----- |
| 1     | Refactor Bootstrap & Cloudflared  | planned  | —          | 3     |
| 2     | Generalize Host Abstraction       | planned  | 1          | TBD   |
| 3     | Add Real Frontline-01 Host        | planned  | 1, 2       | TBD   |
| 4     | True GitOps CI/CD                 | research | 1, 3       | TBD   |

```
Progress: ░░░░░░░░░░ 0%
```

---

### Phase 1: Refactor Bootstrap & Cloudflared

Break the 600-line `bootstrap.nix` monolith into modular, composable files under `modules/outputs/bootstrap/`. Deduplicate cloudflared routes into a single shared source of truth. Fix the K8s cloudflared routing bug.

**Scope:**
- `modules/outputs/bootstrap.nix` → split into `modules/outputs/bootstrap/*.nix`
- Cloudflared routes → shared config in `modules/shared/cloudflared-routes.nix`
- Fix K8s cloudflared route mismatch (port 80 → 30856)

**Plans:** `.planning/phases/01-refactor-bootstrap-cloudflared/`

---

### Phase 2: Generalize Host Abstraction

Make `mkClusterHost` more flexible with configurable options for master address, node labels, taints, and per-host secret paths. Ensure adding a new host requires only: hardware module, host module, secrets file.

**Scope:**
- `modules/lib/mk-cluster-host.nix`
- `modules/profiles/kubernetes/worker.nix`
- `modules/roles/backbone.nix` (secrets extraction)
- `modules/options/quad.nix` (new host-level options)

**Plans:** TBD

---

### Phase 3: Add Real Frontline-01 Host

Configure frontline-01 with real hardware specs, wire it as a K8s worker node, generate per-host secrets, and verify it joins the cluster.

**Scope:**
- `modules/hardware/frontline-01.nix` (real hardware)
- `modules/hosts/frontline-01.nix` (real config)
- `secrets/frontline-01.yaml`
- `modules/outputs/deploy.nix` (frontline-01 target)
- Cloudflared multi-host strategy

**Plans:** TBD

---

### Phase 4: True GitOps CI/CD

Establish full GitOps: push to `main` → CI builds + tests → CD deploys NixOS configs and K8s bootstrap manifests automatically. Research and design the pipeline.

**Scope:**
- Forgejo Actions pipeline redesign
- Automated bootstrap manifest build + apply
- Multi-host deploy-rs automation
- Secret management in CI (sops-nix)
- Git-cliff automated versioning + changelog
- ArgoCD sync policy for K8s apps

**Plans:** `.planning/phases/04-gitops-cicd/` (researching)

### Phase 5: "i also want to setup CI/CD for true git ops, research this"

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 4
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 5 to break down)

### Phase 6: "i also want to setup CI/CD for true git ops, research this"

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 5
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 6 to break down)

### Phase 7: "i also want to setup CI/CD for true git ops, research this"

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 6
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 7 to break down)

### Phase 8: "i also want to setup CI/CD for true git ops, research this"

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 7
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 8 to break down)

---

## Key Constraints

- Source of truth is this repo — no imperative kubectl edits
- Cloudflare tunnel terminates SSL; services behind it are HTTP-only
- Two cloudflared instances (host + K8s) share the same tunnel ID — must have identical routes
- MetalLB assigns `192.168.1.240` to ingress-nginx LoadBalancer
- Deploy via `deploy-rs` with `--skip-checks`
- All fixes must be declarative — nothing imperative outside this repo

## Success Criteria

- [ ] `bootstrap.nix` is under 100 lines (delegates to modules)
- [ ] Cloudflared routes defined in exactly one place
- [ ] Adding a new host requires only: hardware module, host module, secrets file
- [ ] `frontline-01` is a real, deployable K8s worker node
- [ ] Push to `main` triggers full build → test → deploy pipeline
- [ ] `nix build .#bootstrap` produces identical output (modulo intentional fixes)
- [ ] Existing backbone-01 deployment is unaffected by refactor
