# Profile Structure Pattern

## Description

Profile modules are reusable, composable configuration units that can be imported into roles. Each profile focuses on a specific configuration concern (e.g., networking, security, monitoring).

## When to Use

- Create `profiles/{name}.nix` for any configuration that might be reused
- Keep profiles focused on a single concern
- Use the `{ config, pkgs, ... }:` module pattern

## Example

```nix
{ config, pkgs, ... }:

{
  options = {
    enableFubar = lib.mkEnableOption "Enable fubar service";
  };
  
  config = lib.mkIf config.enableFubar {
    services.fubar = {
      enable = true;
      port = 8080;
    };
  };
}
```

## Structural Elements

| Element | Purpose |
|---------|---------|
| `options` | Declare configurable options with mkEnableOption |
| `config` | Define configuration using mkIf conditionals |
| `mkEnableOption` | Create boolean options (enable = true/false) |
| `mkIf` | Conditional configuration application |

## Profile Organization

```
profiles/
├── kubernetes/
│   ├── control-plane.nix   # K8s master configuration
│   ├── worker.nix          # K8s node configuration
│   └── common.nix          # Shared K8s settings
├── networking/
│   ├── common.nix          # Common networking settings
│   └── firewall.nix        # Firewall configuration
└── monitoring/
    └── metrics.nix         # Metrics collection
```

## Anti-Patterns

### Missing Option Declarations
```nix
# BAD: Hardcoding values without options
{
  config = {
    services.myapp.port = 3000;  # Not configurable
  };
}
```

### Large Monolithic Profiles
```nix
# BAD: One profile doing too many things
profiles/default.nix:
  # Handles networking, security, monitoring, storage...
  # Should be split into multiple focused profiles
}
```

### Inconsistent Option Names
```nix
# BAD: Inconsistent naming across profiles
{
  # Some use "enableX", others use "x.enable"
  enableMonitoring = true;
  services.prometheus.enable = true;  # Different pattern
}
```
