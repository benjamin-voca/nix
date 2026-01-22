# Service Module Pattern

## Description

Service modules encapsulate the configuration for a specific application or service. They define options, defaults, and the service configuration using NixOS module system patterns.

## When to Use

- Create `services/{service}.nix` for each application
- Follow the standard module structure with options and config
- Use enable = true/false pattern for service activation

## Example

```nix
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.gitea;
in {
  options.services.gitea = {
    enable = mkEnableOption "Gitea git service";
    package = mkOption {
      type = types.package;
      default = pkgs.gitea;
      description = "Gitea package to use";
    };
    domain = mkOption {
      type = types.str;
      default = "git.example.com";
      description = "Gitea domain";
    };
  };

  config = mkIf cfg.enable {
    services.gitea = {
      inherit cfg.domain;
      package = cfg.package;
    };
  };
}
```

## Structural Elements

| Element | Purpose |
|---------|---------|
| `options` | Declare configurable service options |
| `mkEnableOption` | Create standard enable option |
| `mkOption` | Define option with type and defaults |
| `mkIf cfg.enable` | Conditional service configuration |
| `with lib` | Import library functions |

## Service Organization

```
services/
├── gitea.nix           # Git hosting service
├── buildkite-agent.nix # CI/CD agent
├── otelcol.nix         # OpenTelemetry collector
├── clickhouse.nix      # Analytics database
└── postgres.nix        # PostgreSQL service
```

## Anti-Patterns

### Missing Enable Option
```nix
# BAD: Service always enabled without opt-in
{
  config = {
    services.myapp.enable = true;  # No option to disable
  };
}
```

### Hardcoded Values
```nix
# BAD: No flexibility in configuration
{
  config = {
    services.myapp = {
      host = "localhost";
      port = 5432;
      database = "app_db";  # Not configurable
    };
  };
}
```

### Service Pollution
```nix
# BAD: One service file managing multiple unrelated services
services/monolith.nix:
  # Contains gitea, postgres, redis, nginx...
  # Should be split into separate modules
```
