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

---

## Track 3: Typed Secrets ✅ PHASE 2 DONE

**Goal:** Compile-time validation of SOPS secrets with layering.

**Status:** ✅ Phase 2 complete — library wired, secrets migrated, manual sops.secrets removed.

**Phase 1 delivered:** Infrastructure + layered structure
**Phase 2 delivered:**
- `secrets/roles/backbone.yaml` — 36 encrypted secrets (copied from backbone-01.yaml)
- `secrets/hosts/frontline-01.yaml` — cloudflared-credentials (copied from frontline-01.yaml)
- `machines/consumer.nix` — auto-generates `sops.secrets` from `requiredSecrets` + layered files
- `modules/roles/backbone.nix` — removed 27 manual `sops.secrets` entries
- `.sops.yaml` — creation rules for all layered file paths

**⚠️ Manual step required after deploy:**
```bash
sops updatekeys secrets/roles/backbone.yaml
sops updatekeys secrets/hosts/frontline-01.yaml
```

**Layering model:** shared.yaml → roles/backbone.yaml → hosts/backbone-01.yaml (later wins)

---

## Track 4: Headscale ⏸️ PARKED

**Status:** ⏸️ PARKING until static IP is available.

---

## Architecture Summary

```
machines/default.nix          # Machine registry + secrets.files + requiredSecrets
machines/consumer.nix         # Bridge → auto-generates sops.secrets from layered files
lib/typed-secrets.nix         # 6 functions: hasKey, resolveField, validateRequired, etc.

secrets/
├── shared.yaml               # Cluster-wide (empty)
├── roles/backbone.yaml      # 36 secrets for backbone role ✅ migrated
├── roles/worker.yaml        # Role layer (empty)
├── hosts/backbone-01.yaml    # Machine layer (empty)
├── hosts/frontline-01.yaml   # cloudflared-credentials ✅ migrated
├── backbone-01.yaml.bak     # BACKUP — delete after verification
└── frontline-01.yaml.bak     # BACKUP — delete after verification
```

---

## Open Items

- [ ] Run `sops updatekeys` on migrated secrets files
- [ ] Deploy and verify secrets work correctly
- [ ] Delete `secrets/backbone-01.yaml.bak` and `secrets/frontline-01.yaml.bak` after verification
- [ ] Get static IP from ISP
- [ ] Implement Headscale (after static IP)

---

## Changelog

### 2026-05-19
- ✅ Bootstrap refactor: 14 modules + byte-identical golden test
- ✅ Bootstrap wiring: `config.flake.bootstrap` → refactored output
- ✅ Machine DSL Phase 1-3: complete
- ✅ Typed secrets Phase 1: library + layered structure + registry updates
- ✅ Typed secrets Phase 2: wire library into consumer, migrate secrets, remove manual sops.secrets
- ⏸️ Headscale parked until static IP