# QuadNix Planning — Status

**Date:** 2026-05-19

---

## Track 1: Bootstrap Refactor ✅ COMPLETE + WIRING DONE

**Output:** `modules/outputs/bootstrap/` — 14 modular files + `modules/outputs/default.nix`
**Status:** ✅ All 62 manifest files byte-identical to original

**Wired:** ✅ `config.flake.bootstrap` now points to refactored `modules/outputs/default.nix`.

---

## Track 2: Machine DSL ✅ COMPLETE

**Output:** `machines/default.nix` + `machines/consumer.nix`
**Status:** ✅ Phase 1-3 all complete

```
nix build .#nixosConfigurations.backbone-01.config.system.build.toplevel ✅
nix build .#nixosConfigurations.frontline-01.config.system.build.toplevel ✅
nix eval .#machines.machines --apply 'x: builtins.attrNames x'  → ["backbone-01","frontline-01"] ✅
```

---

## Track 3: Typed Secrets 🔨 PHASE 1 DONE

**Goal:** Compile-time validation of SOPS secrets with layering.

**Output:** `planning/typed-secrets-design.md`
**Status:** 🔨 Phase 1 done. Phase 2 (actual secrets migration) pending.

**Phase 1 delivered:**
- `lib/typed-secrets.nix` — 6 functions: `toHyphenatedKey`, `hasKey`, `resolveField`, `readSopsContent`, `validateRequired`, `toSopsSecrets`
- Layered directory structure:
  - `secrets/shared.yaml` — cluster-wide (empty)
  - `secrets/roles/backbone.yaml` — role layer (empty)
  - `secrets/roles/worker.yaml` — role layer (empty)
  - `secrets/hosts/backbone-01.yaml` — machine layer (empty)
  - `secrets/hosts/frontline-01.yaml` — machine layer (empty)
- `machines/default.nix` — added `secrets.files` and `requiredSecrets`
  - backbone role: 27 required secrets
  - worker role: 1 required secret

**Layering model:** shared.yaml → role.yaml → host.yaml (later wins)

**Phase 2:** Distribute actual secrets from `secrets/backbone-01.yaml` into layered files, wire into `machines/consumer.nix`, remove manual `sops.secrets` from roles.

---

## Track 4: Headscale ⏸️ PARKED

**Status:** ⏸️ PARKING until static IP is available.

---

## Open Items

- [ ] Typed secrets Phase 2: migrate actual secrets into layered files
- [ ] Typed secrets Phase 2: wire `lib/typed-secrets.nix` into `machines/consumer.nix`
- [ ] Typed secrets Phase 2: remove manual `sops.secrets` from `modules/roles/backbone.nix`
- [ ] Get static IP from ISP
- [ ] Implement Headscale (after static IP)

---

## Architecture Summary

```
machines/default.nix          # Machine registry + secrets.layers + requiredSecrets
machines/consumer.nix         # Bridge (sops.secrets still manual in roles for now)
lib/typed-secrets.nix         # Typed secrets library (ready, not wired in yet)

secrets/
├── shared.yaml               # Cluster-wide (empty)
├── roles/backbone.yaml      # Role layer (empty)
├── roles/worker.yaml        # Role layer (empty)
├── hosts/backbone-01.yaml   # Machine layer (empty)
├── hosts/frontline-01.yaml  # Machine layer (empty)
├── backbone-01.yaml        # EXISTING — not migrated yet
└── frontline-01.yaml        # EXISTING — not migrated yet
```

---

## Changelog

### 2026-05-19
- ✅ Bootstrap refactor: 14 modules + byte-identical golden test
- ✅ Bootstrap wiring: `config.flake.bootstrap` → refactored output
- ✅ Machine DSL Phase 1-3: complete
- 🔨 Typed secrets Phase 1: library + layered structure + registry updates
- ⏸️ Headscale parked until static IP