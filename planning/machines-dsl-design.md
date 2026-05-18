# Machine DSL — Design Document

**Date:** 2026-05-19
**Status:** Design complete. Implementation deferred pending bootstrap-refactor Phase 1.

---

## TL;DR

A single `machines/default.nix` file is the source of truth for all machines. Machines reference roles by name. Roles are NixOS modules. K8s resources are NOT in scope — they live in `bootstrap-refactor/`.

**Tailscale status:** Tailscale is the VPN for remote admin access. Defined in the role (or machine via `extraModules`). Headscale can replace it later when a static IP is available.

---

## 1. Directory Structure

```
machines/
├── default.nix              # Machine registry + role registry
├── hardware/                # Hardware modules (symlink to modules/hardware/)
└── roles/                   # Role compositions (symlink to modules/roles/)

bootstrap-refactor/          # K8s bootstrap refactor (separate track)
└── ...

# NOT in scope:
# cluster/ — K8s resources are bootstrap-refactor, not machines/
```

## 2. Nix Schema

```nix
# machines/default.nix
{
  machines = {
    backbone-01 = {
      system = "x86_64-linux";
      hardware = ./hardware/backbone-01.nix;
      role = "backbone";
      sshHost = "backbone01";
      remoteBuild = true;
      taints = [
        { key = "role"; value = "backbone"; effect = "NoSchedule"; }
        { key = "infra"; value = "true"; effect = "NoSchedule"; }
      ];
      extraModules = [
        ({ lib, ... }: {
          boot.loader.grub.enable = lib.mkForce false;
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;
          boot.loader.efi.efiSysMountPoint = "/boot";
        })
      ];
    };

    frontline-01 = {
      system = "x86_64-linux";
      hardware = ./hardware/frontline-01.nix;
      role = "worker";    # renamed from "frontline"
      sshHost = "frontline01";
      remoteBuild = true;
      taints = [
        { key = "role"; value = "frontline"; effect = "NoSchedule"; }
      ];
      extraModules = [
        ({ pkgs, ... }: {
          # cloudflared tunnel for SSH (machine-specific)
        })
      ];
    };
  };

  roles = {
    backbone = {
      module = ./roles/backbone.nix;
      description = "Kubernetes control-plane + ArgoCD + Forgejo + Harbor";
    };

    worker = {
      module = ./roles/worker.nix;
      description = "Kubernetes worker node";
    };
  };
}
```

## 3. Field Reference

### Machine fields

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `system` | string | yes | — | `"x86_64-linux"` |
| `hardware` | path | yes | — | Path to hardware NixOS module |
| `role` | string | yes | — | Key into `roles` block |
| `sshHost` | string | no | machine name | For deploy-rs |
| `remoteBuild` | bool | no | `false` | Cross-compile from darwin |
| `taints` | list | no | `[]` | K8s node taints |
| `extraModules` | list | no | `[]` | Machine-specific NixOS modules |

### Role fields

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `module` | path | yes | NixOS module file |
| `description` | string | no | For docs |

## 4. VPN in the DSL

Tailscale is defined in the role module via `profiles/tailscale.nix`. This is not a top-level field in `machines/default.nix` — it's part of the role's profile composition.

**Migration path for Headscale (future):**
1. Get static IP
2. Deploy Headscale to K8s (`vpn` namespace)
3. Create `profiles/headscale-client.nix`
4. In `machines/default.nix`, swap `profiles/tailscale.nix` → `profiles/headscale-client.nix` in the relevant role(s)
5. Enroll clients with `tailscale up --login-server=https://vpn.quadtech.dev`

**No code change needed to `machines/default.nix`** to swap the VPN backer — it's all in the role module imports.

## 5. Migration Path

### Phase 1: Create registry alongside existing system
1. Create `machines/default.nix` with current hosts
2. Symlink `machines/hardware/` → `modules/hardware/`
3. Symlink `machines/roles/` → `modules/roles/`
4. Create `modules/lib/machine-registry.nix`
5. Create golden test scaffold
6. **Do NOT modify** imports or flake.nix

### Phase 2: Switch flake.nix to use registry
1. Replace `filesIn ./hosts` in `modules/imports.nix` with `./lib/machine-registry.nix`
2. Run golden test
3. Verify store paths identical

### Phase 3: Cleanup
1. Delete `modules/hosts/*.nix`
2. Move hardware/roles to `machines/`
3. Update AGENTS.md

## 6. Open Questions — Resolved

| Q | Decision |
|---|----------|
| Rename `frontline` → `worker`? | ✅ Yes — more descriptive |
| `secrets` field in registry? | ✅ No — `secrets/${hostname}.yaml` convention is sufficient |
| Machine-level services? | ✅ Keep `extraModules` for now |
| Validate role references? | ✅ Rely on Nix errors |
| Keep `mkClusterHost`? | ✅ Yes — clean abstraction boundary |

## 7. Resolved by Bootstrap Refactor

The following were initially in the machine-dsl plan but are now handled by `bootstrap-refactor/`:

- K8s resources in the DSL → ❌ REMOVED from scope. K8s resources are cluster-wide, managed by `bootstrap-refactor/`
- `cluster/` directory → ❌ REMOVED. K8s manifests stay in `bootstrap-refactor/`

## 8. Resolved by Headscale Research

- Headscale public IP requirement → ✅ PARKING. Tailscale is the VPN for now. Headscale planned for when static IP is available.
- WireGuard fallback → ✅ PARKING. Covered in headscale-research.md. Implement when static IP available.