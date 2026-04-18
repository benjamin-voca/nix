# QuadNix Refactor & Multi-Host Expansion

## Vision

Refactor the QuadNix NixOS configuration repo for malleability and extensibility, then add a real second host (frontline-01) to the Kubernetes cluster. The repo should make it easy to add new nodes, services, and ingress routes without touching a 600-line monolith.

## Current State

- **1 real host**: backbone-01 (control-plane, runs everything)
- **3 stub hosts**: backbone-02, frontline-01, frontline-02 (hardware placeholders)
- **600-line `bootstrap.nix`**: all K8s manifests inline, impossible to navigate
- **Duplicated cloudflared config**: host systemd + K8s deployment, routes disagree
- **All secrets in one file**: `secrets/backbone-01.yaml`
- **Hardcoded master address**: worker profile assumes `backbone-01.local`

## Key Constraints

- Source of truth is this repo — no imperative kubectl edits
- Cloudflare tunnel terminates SSL; services behind it are HTTP-only
- Two cloudflared instances (host + K8s) share the same tunnel ID — must have identical routes
- MetalLB assigns `192.168.1.240` to ingress-nginx LoadBalancer
- Deploy via `deploy-rs` with `--skip-checks`

## Success Criteria

- [ ] `bootstrap.nix` is under 100 lines (delegates to modules)
- [ ] Cloudflared routes defined in exactly one place
- [ ] Adding a new host requires only: hardware module, host module, secrets file
- [ ] `frontline-01` is a real, deployable K8s worker node
- [ ] `nix build .#bootstrap` still produces identical output
- [ ] Existing backbone-01 deployment is unaffected by refactor
