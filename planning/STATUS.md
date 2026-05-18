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

## Track 3: Typed Secrets 📋 DESIGN DONE

**Goal:** Compile-time validation of SOPS secrets with layering (shared → role → host overrides).

**Output:** `planning/typed-secrets-design.md`
**Status:** 📋 Design complete. Implementation deferred.

**Key features:**
- Dot-notation field paths (`harbor.admin-password`)
- Layered files: shared.yaml → role.yaml → host.yaml (later wins)
- Compile-time error if required secret field missing
- `lib/typed-secrets.nix` core library

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

- [ ] Implement typed secrets Phase 1 (`lib/typed-secrets.nix`)
- [ ] Migrate secrets layout to layered (shared/roles/hosts)
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
- 📋 Typed secrets design done
- ⏸️ Headscale parked until static IP