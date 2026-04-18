# Phase 2: Generalize Host Abstraction

## Objective
Make `mkClusterHost` and the surrounding module system more flexible so that adding a new host requires only: a hardware module, a host module, and a secrets file — no changes to profiles, roles, or shared config.

## Current Problems

1. **`worker.nix` hardcodes `masterAddress`**: `lib.mkDefault "backbone-01.local"` — workers can't point to a different master without overriding
2. **All secrets in one file**: `backbone.nix` references `secrets/${config.networking.hostName}.yaml` which is good, but the sops.secrets block is huge and role-specific (backbone-only secrets like forgejo-token shouldn't be on frontline)
3. **No per-host options**: Things like `masterAddress`, `nodeLabels`, `taints`, `services` are scattered across host/role/profile modules without a unified options interface
4. **`mkClusterHost` is inflexible**: Takes args but doesn't expose them as NixOS options — can't be configured from other modules

## Plan

### Step 1: Add host-level NixOS options

**Extend** `modules/options/quad.nix` with per-host configuration:

```nix
options.quad.hosts = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      system = lib.mkOption { type = lib.types.str; default = "x86_64-linux"; };
      role = lib.mkOption { type = lib.types.enum [ "backbone" "frontline" ]; };
      hardwareModule = lib.mkOption { type = lib.types.path; };
      k8s = {
        masterAddress = lib.mkOption { type = lib.types.str; default = "backbone-01.local"; };
        taints = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = []; };
        labels = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
      };
      extraModules = lib.mkOption { type = lib.types.listOf lib.types.deferredModule; default = []; };
    };
  });
};
```

### Step 2: Refactor `mkClusterHost` to consume options

Instead of taking a big attrset of args, `mkClusterHost` reads from `config.quad.hosts.<name>`:

```nix
mkClusterHost = name: hostConfig:
  inputs.nixpkgs.lib.nixosSystem {
    system = hostConfig.system;
    modules = [
      inputs.sops-nix.nixosModules.sops
      ({ config, ... }: {
        networking.hostName = name;
        quad.k8s = hostConfig.k8s;
      })
      hostConfig.hardwareModule
      (roleModuleFor hostConfig.role)
    ] ++ hostConfig.extraModules;
  };
```

### Step 3: Make worker profile configurable

**Modify** `modules/profiles/kubernetes/worker.nix`:
```nix
services.kubernetes = {
  roles = [ "node" ];
  masterAddress = lib.mkDefault config.quad.k8s.masterAddress;
};
```

This keeps backward compatibility (`lib.mkDefault`) while allowing per-host override.

### Step 4: Split secrets by role

Create role-specific secret modules:
- `modules/roles/secrets-backbone.nix` — backbone-only secrets (forgejo, argocd, harbor, etc.)
- `modules/roles/secrets-frontline.nix` — frontline secrets (minimal: just sops key, SSH)

The `backbone.nix` role imports `secrets-backbone.nix`, the `frontline.nix` role imports `secrets-frontline.nix`.

### Step 5: Verify

- `nix build .#bootstrap` still works
- `nix build .#nixosConfigurations.backbone-01.config.system.build.toplevel` still works
- Frontline host configs can be built without backbone-specific secrets

## Files Changed

| File | Action |
|------|--------|
| `modules/options/quad.nix` | **Modify** — add host-level options |
| `modules/lib/mk-cluster-host.nix` | **Modify** — consume options instead of args |
| `modules/hosts/backbone-01.nix` | **Modify** — use new options interface |
| `modules/hosts/frontline-01.nix` | **Modify** — use new options interface |
| `modules/profiles/kubernetes/worker.nix` | **Modify** — configurable masterAddress |
| `modules/roles/backbone.nix` | **Modify** — extract secrets to secrets-backbone.nix |
| `modules/roles/secrets-backbone.nix` | **Create** — backbone-specific secrets |
| `modules/roles/secrets-frontline.nix` | **Create** — frontline-specific secrets |

## Estimated Complexity
**Medium** — refactoring existing code to use NixOS options, no new functionality.
