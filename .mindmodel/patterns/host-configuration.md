# Host Configuration Pattern

## Description

Host configuration files define the complete system configuration for a specific NixOS machine. Each host file imports its role composition and applies host-specific settings like networking and hardware.

## When to Use

- Create a new `hosts/{hostname}/default.nix` for each new machine
- Apply host-specific overrides to role configurations
- Configure networking, time zone, and other system-level settings

## Example

```nix
{ config, pkgs, ... }:

{
  imports = [
    ../roles/backbone.nix
    ./hardware.nix
  ];

  networking.hostName = "backbone-01";
  time.timeZone = "America/New_York";

  services.openssh.enable = true;
  boot.loader.systemd-boot.enable = true;
}
```

## Structural Elements

| Element | Purpose |
|---------|---------|
| `imports` | Include role composition and hardware config |
| `networking.hostName` | Unique identifier for the host |
| `time.timeZone` | System timezone setting |
| Service enablements | Enable/disable services at host level |

## Import Relationships

```
hosts/{host}/default.nix
├── roles/{role}.nix
│   ├── profiles/{profile1}.nix
│   ├── profiles/{profile2}.nix
│   └── services/{service}.nix
└── hosts/{host}/hardware.nix
```

## Anti-Patterns

### Generic Hostname Placeholders
```nix
# BAD: Using placeholder names instead of actual hostnames
networking.hostName = "placeholder-host";
```

### Missing Hardware Configuration
```nix
# BAD: Not importing hardware.nix which is required for boot
{
  imports = [ ../roles/backbone.nix ];
  # Missing: ./hardware.nix
}
```

### Inline Secrets
```nix
# BAD: Hardcoding secrets in host configuration
environment.variables = {
  API_SECRET = "my-secret-value";  # Should use SOPS-Nix instead
};
```
