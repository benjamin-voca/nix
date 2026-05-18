# Typed Secrets — Design Document

**Date:** 2026-05-19
**Status:** Design. Implementation deferred to machine DSL Phase 1.

---

## TL;DR

A typed layer over SOPS secrets that catches missing/renamed secrets at compile time instead of deployment time. Two-level layering: **shared** (per-role) and **machine-specific** (per-host overrides).

---

## 1. Problem

Current SOPS secrets in NixOS modules are **opaque strings**:

```nix
sops.secrets = {
  cloudflared-credentials = {
    sopsFile = ./secrets.yaml;
    path = "/run/secrets/cloudflared-credentials.json";
  };
};
```

If `cloudflared-credentials` is missing from the SOPS file, or the path is wrong, you find out at `nix build` time or (worse) at deployment time.

**Goals:**
1. Catch missing secrets at compile time (Nix eval)
2. Catch wrong field paths at compile time
3. Layer secrets: shared (role-level) + per-machine overrides
4. Keep the SOPS workflow intact (encrypted YAML files in Git)

---

## 2. Layering Model

```
secrets/
├── shared.yaml              # Shared secrets (cluster-wide)
│   ├── harbor.admin-password
│   ├── ceph.rgw.access-key
│   └── ceph.rgw.secret-key
│
├── roles/
│   ├── backbone.yaml         # Backbone role secrets
│   │   ├── forgejo.admin-password
│   │   ├── argocd.admin-password
│   │   └── cloudflared.credentials
│   └── worker.yaml          # Worker role secrets
│       └── (usually empty)
│
└── hosts/
    ├── backbone-01.yaml     # Machine-specific overrides
    │   └── openclaw.gateway-token   # Override shared or add new
    └── frontline-01.yaml
```

**Merge order (later wins):**
```
shared.yaml → role.yaml → host.yaml
```

**Use case for layering:**
- `shared.yaml` — cluster-wide credentials (Harbor admin, Ceph S3)
- `roles/backbone.yaml` — secrets specific to backbone services (ArgoCD, Forgejo)
- `hosts/backbone-01.yaml` — machine-specific (OpenClaw API key that only this host needs)

---

## 3. Nix Schema Design

### 3.1 `lib/typed-secrets.nix`

```nix
# lib/typed-secrets.nix
#
# Provides mkTypedSecrets and mkSecretPath for compile-time secret validation.
{pkgs ? throw "pkgs required"}:

let
  lib = pkgs.lib;

  /*
   * Typed secret definition.
   * Fails at Nix eval time if the field doesn't exist in the SOPS file.
   *
   * Example:
   *   mkSecret "harbor.admin-password"
   *   # Produces: { path = "/run/secrets/harbor-admin-password"; sopsFile = ./shared.yaml; }
   *   # If "harbor.admin-password" not in shared.yaml → compile error
   */
  mkSecret = {
    field,           # dot-notation path: "harbor.admin-password"
    sopsFile ? null, # Override SOPS file (default: layered lookup)
    path ? null,     # Override output path (default: inferred from field)
    mode ? "0600",   # File permissions
    owner ? "root",
    group ? "root",
  }: let
    # Convert field "harbor.admin-password" → "harbor-admin-password"
    inferredPath = "/run/secrets/${lib.strings.concatStringsSep "-" (lib.strings.splitString "." field)}";

    resolvedPath = if path != null then path else inferredPath;

    # Layered SOPS file lookup
    layeredSopsFile = if sopsFile != null then sopsFile else null;
  in {
    path = resolvedPath;
    inherit mode owner group;
    sopsFile = layeredSopsFile;  # null means "will be resolved by layered lookup"
    inherit field;
  };

  /*
   * Layer multiple secrets files with override semantics.
   * Files listed later override earlier ones.
   *
   * Example:
   *   layeredSecrets [
   *     ./secrets/shared.yaml
   *     ./secrets/roles/backbone.yaml
   *     ./secrets/hosts/backbone-01.yaml
   *   ]
   */
  layeredSecrets = files: let
    # Verify each file exists
    checkedFiles = builtins.filter (f:
      if builtins.pathExists f then true
      else throw "Typed secrets: SOPS file not found: ${f}"
    ) files;
  in {
    files = checkedFiles;
    # Merge all secrets, later files win
    # Returns list of {field, file} pairs
    resolve = field: let
      result = lib.foldl' (acc: file:
        let content = (builtins.readFile file);
        in
          if builtins.match (".*${lib.replaceStrings ["."] ["\\."] field}.*") content != null
          then file
          else acc
      ) null checkedFiles;
    in
      if result == null
      then throw "Secret field '${field}' not found in any of: ${builtins.concatStringsSep ", " checkedFiles}"
      else result;
  };
```

### 3.2 Machine DSL integration

In `machines/default.nix`:

```nix
# machines/default.nix
{
  machines = {
    backbone-01 = {
      system = "x86_64-linux";
      hardware = ./hardware/backbone-01.nix;
      role = "backbone";
      secrets = {
        files = [
          ./secrets/shared.yaml
          ./secrets/roles/backbone.yaml
          ./secrets/hosts/backbone-01.yaml
        ];
      };
    };

    frontline-01 = {
      system = "x86_64-linux";
      hardware = ./hardware/frontline-01.nix;
      role = "worker";
      secrets = {
        files = [
          ./secrets/shared.yaml
          ./secrets/roles/worker.yaml
          ./secrets/hosts/frontline-01.yaml
        ];
      };
    };
  };

  roles = { ... };
}
```

The role defines **which secrets it requires**:

```nix
# roles/backbone.nix
{
  # Secrets this role needs
  requiredSecrets = [
    "forgejo.admin-password"
    "argocd.admin-password"
    "cloudflared.credentials"
    "harbor.admin-password"
    "ceph.rgw.access-key"
    "ceph.rgw.secret-key"
  ];
}
```

### 3.3 Machine Registry consumes secrets

```nix
# modules/lib/machine-registry.nix
{config, inputs, ...}: let
  registry = import ../../machines/default.nix;
  typedSecrets = import ../../lib/typed-secrets.nix { inherit (inputs.nixpkgs) pkgs; };
in {
  config.quad.hosts = builtins.mapAttrs (name: machine: let
    role = registry.roles.${machine.role};
    secretsLayer = typedSecrets.layeredSecrets machine.secrets.files;

    # Validate all required secrets exist in the layered files
    validatedSecrets = builtins.map (field: let
      sopsFile = secretsLayer.resolve field;
    in
      typedSecrets.mkSecret {
        inherit field;
        sopsFile = sopsFile;
      }
    ) (role.requiredSecrets or []);

    # Build extraModules with typed secrets
    secretModules = [{ lib, ... }: {
      sops.secrets = builtins.listToAttrs (
        builtins.map (s: {
          name = lib.strings.replaceStrings ["."] ["-"] s.field;
          value = {
            inherit (s) path;
            sopsFile = s.sopsFile;
            mode = "0600";
            owner = "root";
            group = "root";
          };
        }) validatedSecrets
      );
    }];

  in
    config.quad.lib.mkClusterHost {
      # ... existing fields ...
      extraModules = machine.extraModules ++ secretModules;
    }
  ) registry.machines;
}
```

---

## 4. Compile-Time Validation

### 4.1 Field existence

If a required secret field doesn't exist in any layered file:

```
error: Secret field 'forgejo.admin-password' not found in any of:
  /Users/benjamin/Personal/nix/secrets/shared.yaml,
  /Users/benjamin/Personal/nix/secrets/roles/backbone.yaml,
  /Users/benjamin/Personal/nix/secrets/hosts/backbone-01.yaml
```

This happens at `nix eval` time — before you even run `nix build`.

### 4.2 File existence

If a SOPS file doesn't exist:

```
error: Typed secrets: SOPS file not found: /Users/benjamin/Personal/nix/secrets/hosts/new-host.yaml
```

### 4.3 Path conflicts

If two machines define the same secret path differently, Nix catches it when both try to set `sops.secrets`:

```
error: The option `quad.hosts.backbone-01.sops.secrets.cloudflared-credentials.path'
in `modules/hosts/backbone-01.nix' is already claimed by
`modules/hosts/frontline-01.nix'.
```

---

## 5. SOPS File Structure

Example `secrets/shared.yaml`:

```yaml
harbor:
    admin-password: ENC[AES256_GCM,...]
    registry-password: ENC[AES256_GCM,...]
ceph:
    rgw:
        access-key: ENC[AES256_GCM,...]
        secret-key: ENC[AES256_GCM,...]
```

Example `secrets/roles/backbone.yaml`:

```yaml
forgejo:
    admin-password: ENC[AES256_GCM,...]
    runner-token: ENC[AES256_GCM,...]
argocd:
    admin-password: ENC[AES256_GCM,...]
cloudflared:
    credentials: ENC[AES256_GCM,...]
```

Example `secrets/hosts/backbone-01.yaml`:

```yaml
openclaw:
    gateway-token: ENC[AES256_GCM,...]
    minimax-api-key: ENC[AES256_GCM,...]
```

---

## 6. Open Questions

| Q | Decision |
|---|----------|
| SOPS file location | `secrets/` at repo root (current convention) |
| Dot-notation vs flat keys | Dot-notation (`harbor.admin-password`) — groups logically |
| How to handle secrets that exist in multiple files | Later file wins — explicit per-machine overrides |
| How to mark optional vs required | Required by default; mark optional per-field in role |
| Migration from current inline SOPS | Phase 4 of machine DSL migration |

---

## 7. Migration from Current System

**Current** (in `modules/roles/backbone.nix`):
```nix
sops.secrets = {
  cloudflared-credentials = {
    sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    path = "/run/secrets/cloudflared-credentials.json";
  };
};
```

**After** (in `machines/default.nix`):
```nix
backbone-01 = {
  secrets.files = [
    ./secrets/shared.yaml
    ./secrets/roles/backbone.yaml
    ./secrets/hosts/backbone-01.yaml
  ];
};
```

**Role defines requirements** (in `roles/backbone.nix`):
```nix
requiredSecrets = [
  "cloudflared.credentials"
  "forgejo.admin-password"
  # ...
];
```

The machine registry generates the `sops.secrets` Nix config automatically.

---

## 8. Files to Create

```
lib/typed-secrets.nix              # Core typed secrets library
machines/secrets/                  # Secret files directory
machines/secrets/shared.yaml       # Cluster-wide shared secrets
machines/secrets/roles/            # Per-role secret files
machines/secrets/hosts/            # Per-host secret files
```

## 9. Files to Modify

```
modules/lib/machine-registry.nix   # Consume typed-secrets.nix
machines/default.nix               # Add secrets.files field
modules/roles/backbone.nix         # Add requiredSecrets attr
modules/roles/worker.nix           # Add requiredSecrets attr (likely empty)
```