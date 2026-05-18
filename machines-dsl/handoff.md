# Machine DSL Phase 1 — Implementation Handoff

**Date:** 2026-05-19
**Status:** ✅ Complete

---

## What Was Created

### New Files
| File | Purpose |
|------|---------|
| `machines/default.nix` | Machine registry — source of truth for all hosts and roles |
| `machines/consumer.nix` | NixOS module bridge — reads registry, produces `config.quad.hosts` |
| `machines/hardware/` | Symlink → `../modules/hardware/` |
| `machines/roles/` | Symlink → `../modules/roles/` |
| `modules/roles/worker.nix` | Copy of `frontline.nix` (role renamed for clarity) |
| `tests/nix/machines/registry-test.nix` | Structural validation test |

### Modified Files
| File | Change |
|------|--------|
| `modules/hosts/frontline-01.nix` | `roleModule` changed from `../roles/frontline.nix` → `../roles/worker.nix` |

### NOT Modified (Phase 1 constraints respected)
| File | Reason |
|------|--------|
| `modules/imports.nix` | Not adding consumer.nix yet — Phase 2 |
| `flake.nix` | No changes — Phase 2 |
| `modules/hosts/backbone-01.nix` | Unchanged, still works |
| `modules/roles/frontline.nix` | Kept for safety, no references remain |
| `modules/lib/mk-cluster-host.nix` | Unchanged, abstraction boundary preserved |

---

## Architecture Decision: consumer.nix Location

**Planned:** `modules/lib/machine-registry.nix`
**Actual:** `machines/consumer.nix`

**Reason:** `modules/imports.nix` auto-discovers ALL `.nix` files in `modules/lib/` via `filesIn ./lib`. Placing the registry consumer there would immediately wire it into the module system, causing `config.quad.hosts` conflicts with existing host definitions. Putting it in `machines/` (which is not in the auto-discovery path) keeps it inert until Phase 2 explicitly adds it to imports.

**Phase 2 action:** Add `./machines/consumer.nix` to `modules/imports.nix` (replacing `filesIn ./hosts`).

---

## Validation Results

| Check | Result |
|-------|--------|
| `nix-instantiate --eval machines/default.nix` | ✅ Evaluates cleanly |
| `nix-instantiate --eval machines/default.nix -A machines.backbone-01.role` | ✅ `"backbone"` |
| `nix-instantiate --eval machines/default.nix -A machines.frontline-01.role` | ✅ `"worker"` |
| `nix-instantiate --eval machines/default.nix -A roles.worker.description` | ✅ `"Kubernetes worker node"` |
| `nix build .#nixosConfigurations.backbone-01.config.system.build.toplevel --dry-run` | ✅ Success |
| `nix build .#nixosConfigurations.frontline-01.config.system.build.toplevel --dry-run` | ✅ Success |
| `nix flake check` | ✅ All checks passed |
| `nix-instantiate --eval tests/nix/machines/registry-test.nix` | ✅ `true` |
| `nix-instantiate --parse machines/consumer.nix` | ✅ Parses cleanly |

---

## Registry Schema (machines/default.nix)

```nix
{
  machines = {
    backbone-01 = {
      system, hardware, role, sshHost, remoteBuild, taints, extraModules
    };
    frontline-01 = {
      system, hardware, role ("worker"), sshHost, remoteBuild, taints, extraModules
    };
  };
  roles = {
    backbone = { module, description };
    worker   = { module, description };
  };
}
```

---

## Known Issues / Follow-ups

### 1. `frontline.nix` still exists in `modules/roles/`
The old role file is kept as a safety net. No host references it anymore (frontline-01 now uses worker.nix). Can be deleted in Phase 3 cleanup.

### 2. Symlink caveat
`machines/hardware/` and `machines/roles/` are symlinks to `modules/`. This means the registry references paths through `machines/roles/worker.nix` which resolves to `modules/roles/worker.nix`. When roles import relative paths (e.g., `../profiles/base.nix`), Nix resolves these relative to the *target* (`modules/roles/`), not the symlink. This works correctly.

### 3. The `extraModules` for frontline-01 contains cloudflared tunnel credentials
These are hardcoded in the machine-level extraModules (copied from the original host definition). This is correct for Phase 1 — machine-specific config lives in `extraModules`.

### 4. Role rename: `frontline` → `worker`
The role file was renamed, but the K8s taint on frontline-01 still says `value = "frontline"`. This is intentional — the taint is a K8s label, not a Nix role name.

---

## Phase 2 Plan

1. **Modify `modules/imports.nix`**: Replace `filesIn ./hosts` with `./machines/consumer.nix`
2. **Add `machines` to flake outputs**: `nix eval .#machines` should work
3. **Golden test**: Verify `nixosConfigurations.*.config.system.build.toplevel` produces identical store paths between old and new system
4. **Wire `machines` output**: Add to `flake.nix` for discoverability

## Phase 3 Plan

1. **Delete** `modules/hosts/backbone-01.nix`, `modules/hosts/frontline-01.nix`
2. **Delete** `modules/roles/frontline.nix` (superseded by worker.nix)
3. **Replace symlinks**: Move hardware/roles into `machines/` directly (or keep symlinks — both work)
4. **Update** `planning/STATUS.md` and `AGENTS.md`

---

## Git Status

All changes staged but NOT committed:
```
new file:   machines/consumer.nix
new file:   machines/default.nix
new file:   machines/hardware          (symlink)
new file:   machines/roles             (symlink)
modified:   modules/hosts/frontline-01.nix
new file:   modules/roles/worker.nix
new file:   tests/nix/machines/registry-test.nix
```
