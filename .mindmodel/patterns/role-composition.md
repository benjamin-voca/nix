# Role Composition Pattern

## Description

Role composition files combine multiple profiles and services into a cohesive configuration for a specific host function. Roles define what a type of machine does (e.g., control plane vs. worker node).

## When to Use

- Create `roles/{role}.nix` to define machine types
- Compose profiles that represent configuration concerns
- Import service modules for software to run on this role

## Example

```nix
{ config, pkgs, ... }:

{
  imports = [
    ../profiles/kubernetes/control-plane.nix
    ../profiles/networking/common.nix
    ../services/gitea.nix
  ];

  # Role-specific configuration
  kubernetes.role = "control-plane";
  
  # Enable services for this role
  services.gitea.enable = true;
}
```

## Structural Elements

| Element | Purpose |
|---------|---------|
| `imports` | Include relevant profiles and services |
| `kubernetes.role` | Designates control-plane or worker |
| Service enablements | Enable services specific to this role |

## Import Relationships

```
roles/backbone.nix (Control Plane)
├── profiles/kubernetes/control-plane.nix
├── profiles/kubernetes/common.nix
├── profiles/networking/common.nix
└── services/gitea.nix

roles/frontline.nix (Worker)
├── profiles/kubernetes/worker.nix
├── profiles/kubernetes/common.nix
└── profiles/networking/common.nix
```

## Anti-Patterns

### Commented-Out Service Imports
```nix
# BAD: Commented imports make it unclear what's intended
{
  imports = [
    ../profiles/base.nix
    # ../services/postgres.nix  # Why is this commented?
    # ../services/redis.nix     # Technical debt
  ];
}
```

### Monolithic Role Files
```nix
# BAD: Putting everything in one file instead of composing profiles
{
  imports = [ ../profiles/base.nix ];
  
  # Hundreds of lines of inline configuration
  services.httpd.enable = true;
  services.database.enable = true;
  # ... more inline config
}
```

### Role Mixing
```nix
# BAD: Combining worker and control-plane concerns in one role
{
  imports = [
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/worker.nix  # Conflicting roles
  ];
}
```
