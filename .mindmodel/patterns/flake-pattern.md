# Flake Pattern

## Description

The flake.nix file is the entry point for the NixOS configuration. It declares inputs (dependencies), outputs (available configurations), and integrates with deploy-rs for atomic deployments.

## When to Use

- Define all external dependencies as flake inputs
- Export system configurations via nixosConfigurations
- Configure deploy-rs targets for each host
- Update inputs when adding new packages or services

## Example

```nix
{
  description = "QuadNix - NixOS Infrastructure";

  inputs = {
    nixpkgs.url = "github:nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs = { self, nixpkgs, sops-nix, deploy-rs }: {
    nixosConfigurations = {
      backbone-01 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ 
          ./hosts/backbone-01/default.nix
          sops-nix.nixosModules.sops
        ];
      };
      backbone-02 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ 
          ./hosts/backbone-02/default.nix
          sops-nix.nixosModules.sops
        ];
      };
      frontline-01 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ 
          ./hosts/frontline-01/default.nix
          sops-nix.nixosModules.sops
        ];
      };
      frontline-02 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ 
          ./hosts/frontline-02/default.nix
          sops-nix.nixosModules.sops
        ];
      };
    };
    
    deploy = {
      magic = {
        profiles.system = {
          user = "benjamin";
          sshUser = "benjamin";
          path = deploy-rs.lib.${hostPlatform}.deploySystem {
            name = "backbone-01";
            profile = self.nixosConfigurations.backbone-01;
          };
        };
        hosts = [
          deploy-rs.lib.${hostPlatform} deploy.hosts.backbone-01
        ];
      };
    };
  };
}
```

## Structural Elements

| Element | Purpose |
|---------|---------|
| `inputs` | External dependencies (nixpkgs, sops-nix, deploy-rs) |
| `nixosConfigurations` | Export system configurations |
| `modules` | List of NixOS modules to include |
| `deploy` | deploy-rs deployment targets |

## Input Sources

| Input | Source | Purpose |
|-------|--------|---------|
| `nixpkgs` | github:nixpkgs/nixos-unstable | Core packages and modules |
| `sops-nix` | github:Mic92/sops-nix | Secrets management |
| `deploy-rs` | github:serokell/deploy-rs | Atomic deployments |

## Anti-Patterns

### Unpinned Inputs
```nix
# BAD: Using unstable without specific revision
{
  inputs = {
    nixpkgs.url = "github:nixpkgs/nixos-unstable";
    # No rev or flake.lock pinning
  };
}
```

### Missing Hosts
```nix
# BAD: Forgetting to add a new host to nixosConfigurations
nixosConfigurations = {
  backbone-01 = ...;
  backbone-02 = ...;
  # frontline-01 missing from outputs
};
```

### Hardcoded Platform
```nix
# BAD: Using literal "x86_64-linux" instead of variable
system = "x86_64-linux";  # Should use ${hostPlatform}
```
