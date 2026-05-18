# QuadNix Planning — Status

**Date:** 2026-05-19

---

## Track 1: Bootstrap Refactor ✅ COMPLETE + WIRING DONE

**Goal:** Break `modules/outputs/bootstrap.nix` (1500 lines) into modular pieces.

**Output:** `modules/outputs/bootstrap/` — 14 modular files + `modules/outputs/default.nix`
**Status:** ✅ All 62 manifest files byte-identical to original

**Wired:** ✅ `config.flake.bootstrap` now points to refactored `modules/outputs/default.nix`. Old `bootstrap.nix` deleted.

---

## Track 2: Machine DSL ✅ COMPLETE

**Goal:** Single `machines/default.nix` as source of truth for NixOS hosts.

**Output:** `machines/default.nix` + `machines/consumer.nix`
**Status:** ✅ Phase 1-3 all complete:

- ✅ Phase 1: Create registry alongside existing system
- ✅ Phase 2: Wire `machines/consumer.nix` into `modules/imports.nix`, delete old host files
- ✅ Phase 3: Cleanup old files (`modules/hosts/*.nix`, `modules/roles/frontline.nix`)
- ✅ Phase 4: `nix eval .#machines` works (machines + roles attrsets)

**Validation:**
```
nix build .#nixosConfigurations.backbone-01.config.system.build.toplevel ✅
nix build .#nixosConfigurations.frontline-01.config.system.build.toplevel ✅
nix eval .#machines.machines.backbone-01.role → "backbone" ✅
nix eval .#machines.machines.frontline-01.role → "worker" ✅
nix flake check ✅
```

**Directory structure:**
```
machines/
├── default.nix           # Machine registry (source of truth)
└── consumer.nix         # NixOS module bridge → config.quad.hosts

modules/                   # Old host/role files deleted
├── hosts/                 # DELETED
├── roles/frontline.nix   # DELETED (renamed to worker.nix)
└── ...
```

---

## Track 3: Typed Secrets 🔨 IN PROGRESS

**Goal:** Compile-time validation of SOPS secrets with layering (shared → role → host overrides).

**Output:** `lib/typed-secrets.nix` + layered secrets directory structure
**Status:** 🔨 Phase 1 infrastructure complete. Layered files empty — actual migration is Phase 2.

**Completed:**
- ✅ `lib/typed-secrets.nix` — core library with `toHyphenatedKey`, `hasKey`, `resolveField`, `readSopsContent`, `validateRequired`, `toSopsSecrets`
- ✅ Layered directory structure: `secrets/shared.yaml`, `secrets/roles/`, `secrets/hosts/`
- ✅ `machines/default.nix` updated with `secrets.files` per machine and `requiredSecrets` per role
- ✅ All evaluations pass (`nix eval .#machines`, `nix flake check`)

**Remaining (Phase 2 of typed secrets):**
- [ ] Migrate actual secrets from `secrets/backbone-01.yaml` into layered files
- [ ] Wire `lib/typed-secrets.nix` into `machines/consumer.nix` to auto-generate `sops.secrets`
- [ ] Remove manual `sops.secrets` from `modules/roles/backbone.nix`

**Key features:**
- Hyphenated flat keys matching existing SOPS files (e.g., `harbor-admin-password`)
- Layered files: shared.yaml → role.yaml → host.yaml (later wins)
- Compile-time error if required secret field missing
- `lib/typed-secrets.nix` core library

**Role requiredSecrets:**
- `backbone`: 27 secrets (cloudflared, forgejo, argocd, harbor, ceph, minecraft, verdaccio, erpnext, openclaw, orkestr, librechat, tailscale)
- `worker`: 1 secret (cloudflared-credentials)

---

## Track 4: Headscale ⏸️ PARKED

**Status:** ⏸️ PARKING until static IP is available.

---

## Resolved Decisions

| Decision | Outcome |
|----------|---------|
| K8s resources at machine level? | ❌ No — cluster-wide only |
| Symlinks in machines/? | ❌ Removed — direct paths to modules/ |
| Role rename `frontline` → `worker`? | ✅ Yes |
| Old host files deleted? | ✅ Yes — registry is sole source of truth |
| `index.nix` vs `default.nix`? | `default.nix` |
| Headscale now or later? | Later — park until static IP |

---

## Open Items

- [x] Implement typed secrets Phase 1 (`lib/typed-secrets.nix`)
- [ ] Migrate secrets layout to layered (shared/roles/hosts) — Phase 2
- [ ] Wire typed-secrets into consumer.nix — Phase 2
- [ ] Get static IP from ISP
- [ ] Implement Headscale (after static IP)

---

## Architecture Summary (post-Phases 2-3)

```
flake.nix
├── nixosConfigurations.backbone-01    ← machines/default.nix → consumer.nix
├── nixosConfigurations.frontline-01   ← machines/default.nix → consumer.nix
├── packages.bootstrap                  ← modules/outputs/default.nix
└── machines                           ← machines/default.nix (direct eval)

Source of truth: machines/default.nix
No more: modules/hosts/*.nix, modules/roles/frontline.nix
```

---

## Changelog

### 2026-05-19
- ✅ Bootstrap refactor: 14 modules + byte-identical golden test
- ✅ Bootstrap wiring: `config.flake.bootstrap` → refactored output
- ✅ Machine DSL Phase 1: registry + consumer + tests
- ✅ Machine DSL Phase 2-3: wire consumer into imports, delete old files
- ✅ All nixosConfigurations build and flake check passes
- 🔨 Typed secrets Phase 1: core library + layered structure + registry
- ⏸️ Headscale parked until static IP

### 2026-05-19 (typed-secrets phase 1)
- ✅ `lib/typed-secrets.nix` — core library (6 functions)
- ✅ Layered secrets directory: `secrets/{shared,roles/,hosts/}` (empty YAML files)
- ✅ Registry: `secrets.files` per machine, `requiredSecrets` per role
- ✅ Backbone role: 27 requiredSecrets, Worker role: 1 requiredSecret
- ✅ `nix eval .#machines` and `nix flake check` pass
- 🔜 Phase 2: migrate actual secrets + wire into consumer