# Machine DSL Phases 2-3 — Implementation Handoff

**Date:** 2026-05-19
**Status:** ✅ Complete

---

## Summary

Wired the machine registry into the flake, replaced old host files with consumer module, renamed bootstrap refactor to main bootstrap, and cleaned up old files.

---

## What Was Changed

### Track A: Bootstrap Refactor Wiring

| File | Change |
|------|--------|
| `modules/outputs/default.nix` | Renamed `config.flake.bootstrapRefactored` → `config.flake.bootstrap` |
| `flake.nix` | Removed `bootstrapRefactored` and typo `boostrap` from packages; removed golden test check |
| `modules/outputs/bootstrap.nix` | **DELETED** — old 1500-line monolith, replaced by refactored version |
| `tests/bootstrap-golden-test.nix` | **DELETED** — referenced removed `bootstrapRefactored` |
| `modules/outputs/bootstrap-apps.nix` | **DELETED** — superseded by refactored bootstrap |
| `modules/outputs/bootstrap-infra.nix` | **DELETED** — superseded by refactored bootstrap |

### Track B: Machine DSL Phase 2 — Wire Consumer

| File | Change |
|------|--------|
| `modules/imports.nix` | Replaced `filesIn ./hosts` with `[ ../machines/consumer.nix ]` |
| `flake.nix` | Added `machines = import ./machines/default.nix;` to flakeOutputs |
| `machines/default.nix` | Changed paths from symlink-based (`./roles/`, `./hardware/`) to direct (`../modules/roles/`, `../modules/hardware/`) |
| `machines/hardware` | **DELETED** — broken symlink, paths now direct |
| `machines/roles` | **DELETED** — broken symlink, paths now direct |

### Track C: Machine DSL Phase 3 — Cleanup

| File | Change |
|------|--------|
| `modules/hosts/backbone-01.nix` | **DELETED** — superseded by registry + consumer |
| `modules/hosts/frontline-01.nix` | **DELETED** — superseded by registry + consumer |
| `modules/roles/frontline.nix` | **DELETED** — superseded by worker.nix |
| `modules/hosts/` | **DELETED** — empty directory removed |
| `AGENTS.md` | Updated to reflect machine registry structure, removed `modules/hosts/*.nix` references |
| `planning/STATUS.md` | Updated Track 1 and Track 2 to complete |

### New Files

| File | Purpose |
|------|---------|
| `tests/nix/machines/golden-test.sh` | Build verification script for future comparisons |
| `tests/nix/machines/baseline-paths.txt` | Baseline documentation |

---

## Deviations from Plan

### 1. Symlink issue in `machines/default.nix`

**Problem:** The original `machines/default.nix` used symlinks (`./roles/backbone.nix` → `../modules/roles/backbone.nix`). When Nix loaded files through these symlinks, relative imports inside the role files (e.g., `../profiles/base.nix`) resolved relative to the symlink path (`machines/profiles/base.nix`) instead of the real path (`modules/profiles/base.nix`).

**Fix:** Changed `machines/default.nix` to reference paths directly:
- `./roles/backbone.nix` → `../modules/roles/backbone.nix`
- `./hardware/backbone-01.nix` → `../modules/hardware/backbone-01.nix`

Removed the `machines/hardware` and `machines/roles` symlinks entirely.

**Lesson:** Nix resolves relative paths based on the path string it uses to track the file, not the symlink target. Symlinks in Nix flakes cause path resolution issues.

### 2. `mk-cluster-host.nix` import method

**Problem:** Task specified `(import ./lib/mk-cluster-host.nix inputs)` but this is a NixOS module (takes `{ inputs, config, ... }`), not a function accepting a plain `inputs` argument. Calling it with `inputs` as a positional arg fails.

**Fix:** Did NOT explicitly import `mk-cluster-host.nix`. It's already imported via `filesIn ./lib` in `modules/imports.nix`. The NixOS module system merges all modules before evaluation, so `config.quad.lib.mkClusterHost` is available to `consumer.nix` regardless of import order.

### 3. Empty `checks` attrset

The golden test check was removed since it compared old vs refactored bootstrap. Left an empty `checks` attrset in `flake.nix`'s `flakeOutputs` — the real checks come from `modules/outputs/checks.nix` which auto-discovers via `filesIn ./outputs`.

---

## Validation Results

| Check | Result |
|-------|--------|
| `nix build .#packages.x86_64-linux.bootstrap --dry-run` | ✅ Evaluates (61 derivations) |
| `nix build .#nixosConfigurations.backbone-01.config.system.build.toplevel --dry-run` | ✅ Evaluates |
| `nix build .#nixosConfigurations.frontline-01.config.system.build.toplevel --dry-run` | ✅ Evaluates |
| `nix eval .#machines.machines.backbone-01.role` | ✅ `"backbone"` |
| `nix eval .#machines.machines.frontline-01.role` | ✅ `"worker"` |
| `nix eval .#machines.machines --apply 'x: builtins.attrNames x'` | ✅ `["backbone-01","frontline-01"]` |
| `nix eval .#machines.roles --apply 'x: builtins.attrNames x'` | ✅ `["backbone","worker"]` |
| `nix flake check` | ✅ All checks passed |

---

## Current Architecture

### Import Flow
```
flake.nix
  → eval = lib.evalModules { modules = [ ./modules/top.nix ]; }
    → modules/top.nix → modules/imports.nix
      → filesIn ./options  (flake, quad options)
      → filesIn ./outputs  (bootstrap, nixosConfigurations, deploy, helm, checks)
      → [ ../machines/consumer.nix ]  (reads registry → config.quad.hosts)
      → filesIn ./lib  (mk-cluster-host.nix)
```

### Machine Flow
```
machines/default.nix  (registry: machines + roles)
  → machines/consumer.nix  (NixOS module bridge)
    → config.quad.lib.mkClusterHost  (from modules/lib/mk-cluster-host.nix)
      → config.quad.hosts  (NixOS configurations keyed by hostname)
        → modules/outputs/nixos-configurations.nix  (exposes as flake.nixosConfigurations)
```

### Flake Outputs
```
nix eval .#machines                    — full registry (machines + roles)
nix build .#packages.x86_64-linux.bootstrap  — K8s bootstrap manifests
nix build .#nixosConfigurations.<host>.config.system.build.toplevel  — NixOS system
```

---

## Files Remaining from Phase 1

- `tests/nix/machines/registry-test.nix` — structural validation (still valid)
- `machines-dsl/handoff.md` — Phase 1 handoff document (historical reference)

---

## Next Steps

1. **Typed Secrets Phase 1** — Implement `lib/typed-secrets.nix` (see `planning/typed-secrets-design.md`)
2. **Headscale** — Parked until static IP is available
3. **Full build verification** — Push to hosts with `deploy-rs` to verify actual deployment works
