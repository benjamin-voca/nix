# Hardware Configuration Pattern

## Description

Hardware configuration files contain machine-specific hardware specifications required for boot and device initialization. Each host must have a complete hardware.nix file with actual device identifiers.

## When to Use

- Create `hosts/{host}/hardware.nix` for each new host
- Include actual UUIDs, device paths, and firmware settings
- Run `nixos-generate-config` to generate initial hardware.nix

## Example

```nix
{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" ];
  boot.initrd.kernelModules = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/aaaaaaaa-bbbb-cccc-dddd-eeeeeeee";
    fsType = "ext4";
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/ffffffff-gggg-hhhh-iiii-jjjjjjjj"; }
  ];
}
```

## Structural Elements

| Element | Purpose |
|---------|---------|
| `boot.initrd.availableKernelModules` | Modules to load for boot |
| `fileSystems."/"` | Root filesystem configuration |
| `swapDevices` | Swap partition configuration |
| `hardware.deviceTree` | Device tree overlays |

## Hardware File Locations

```
hosts/
├── backbone-01/
│   ├── default.nix
│   └── hardware.nix
├── backbone-02/
│   ├── default.nix
│   └── hardware.nix
├── frontline-01/
│   ├── default.nix
│   └── hardware.nix
└── frontline-02/
    ├── default.nix
    └── hardware.nix
```

## Anti-Patterns

### Placeholder UUIDs
```nix
# BAD: Using placeholder values that won't work
{
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/PLACEHOLDER-UUID";
    fsType = "ext4";
  };
}
```

### Incomplete Hardware Config
```nix
# BAD: Missing essential hardware settings
{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];
  # Missing: fileSystems, swapDevices, boot.initrd
}
```

### Copy-Paste Without Updates
```nix
# BAD: Using hardware config from another host
# backbone-01/hardware.nix copied to backbone-02
# but still contains backbone-01's disk UUIDs
```
