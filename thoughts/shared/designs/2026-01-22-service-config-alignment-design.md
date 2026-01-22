# Service Configuration Alignment Design

**Date:** 2026-01-22
**Author:** QuadNix System
**Status:** Approved

## Executive Summary

This document outlines the chosen approach for aligning Kubernetes control-plane and Gitea service configurations with current NixOS module options. The goal is to ensure consistent, declarative configuration management across all service deployments using NixOS's module system.

## Problem Statement

Currently, Kubernetes control-plane and Gitea services are configured through a mix of:
- Manual configuration files
- Outdated NixOS module definitions
- Environment-specific overrides

This inconsistency leads to:
- Configuration drift between environments
- Difficulty in reproducing identical deployments
- Maintenance burden when updating service versions
- Lack of single source of truth for service configurations

## Chosen Approach

### Unified Module Strategy

Adopt a **layered configuration approach** using NixOS modules:

```
nix/
├── modules/
│   ├── shared/
│   │   ├── common.nix          # Shared options and defaults
│   │   ├── kubernetes-common.nix
│   │   └── gitea-common.nix
│   ├── kubernetes/
│   │   ├── control-plane.nix   # Control-plane specific config
│   │   └── worker.nix
│   └── gitea/
│       ├── server.nix
│       └── runner.nix
├── services/
│   ├── kubernetes/
│   └── gitea/
└── flake.nix
```

### Key Design Principles

1. **Single Source of Truth**: All configurations defined in Nix modules
2. **Declarative Options**: Use NixOS `options` for all configurable values
3. **Environment Profiles**: Environment-specific settings via profile composition
4. **Version Pinning**: Services pinned to specific versions with upgrade paths

## Kubernetes Control-Plane Alignment

### Current State Analysis

| Component | Current Config Location | Target Module |
|-----------|------------------------|---------------|
| etcd | `/etc/kubernetes/etcd.conf` | `kubernetes.control-plane.etcd` |
| API Server | `/etc/kubernetes/api-server.yaml` | `kubernetes.control-plane.apiServer` |
| Scheduler | `/etc/kubernetes/scheduler.yaml` | `kubernetes.control-plane.scheduler` |
| Controller Manager | `/etc/kubernetes/controller-manager.yaml` | `kubernetes.control-plane.controllerManager` |

### Target Module Structure

```nix
{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.services.kubernetes.control-plane;
in {
  options.services.kubernetes.control-plane = {
    enable = mkEnableOption "Kubernetes control-plane";
    
    etcd = {
      enable = mkEnableOption "etcd";
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/etcd";
      };
      cluster = mkOption {
        type = types.listOf types.str;
        default = [];
      };
    };
    
    apiServer = {
      enable = mkEnableOption "API server";
      advertiseAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
      };
      etcdServers = mkOption {
        type = types.listOf types.str;
        default = ["http://localhost:2379"];
      };
    };
    
    # Scheduler and ControllerManager options...
  };
  
  config = mkIf cfg.enable {
    # Implementation generation logic
  };
}
```

## Gitea Service Alignment

### Current State Analysis

| Component | Current Config Location | Target Module |
|-----------|------------------------|---------------|
| App | `/etc/gitea/conf/app.ini` | `services.gitea` (existing) |
| Database | `/etc/gitea/conf/database.ini` | `services.gitea.database` |
| SSH | `/etc/gitea/conf/ssh.conf` | `services.gitea.ssh` |

### Enhancement Strategy

1. **Extend existing `services.gitea` module** with additional options
2. **Add database migration support** for schema updates
3. **Implement SSH configuration** through module options
4. **Add backup/restore** primitives

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Create shared module library
- [ ] Define base option structures
- [ ] Set up CI pipeline for module validation

### Phase 2: Kubernetes Control-Plane (Week 3-4)
- [ ] Implement `kubernetes.control-plane` module
- [ ] Migrate existing configurations
- [ ] Test with staging environment
- [ ] Document upgrade procedures

### Phase 3: Gitea Enhancement (Week 5-6)
- [ ] Extend `services.gitea` module
- [ ] Add database migration handling
- [ ] Implement SSH key management
- [ ] Create backup automation

### Phase 4: Migration & Cleanup (Week 7-8)
- [ ] Production deployment
- [ ] Decommission legacy config files
- [ ] Update documentation
- [ ] Team training

## Configuration Examples

### Kubernetes Control-Plane Deployment

```nix
# cluster-prod.nix
{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/kubernetes/control-plane.nix
    ./modules/shared/profiles/prod.nix
  ];

  services.kubernetes.control-plane = {
    enable = true;
    
    etcd = {
      enable = true;
      dataDir = "/var/lib/etcd/prod";
    };
    
    apiServer = {
      enable = true;
      advertiseAddress = "10.0.0.1";
      etcdServers = [
        "https://etcd-0.quadnix.internal:2379"
        "https://etcd-1.quadnix.internal:2379"
        "https://etcd-2.quadnix.internal:2379"
      ];
    };
  };
}
```

### Gitea Service Deployment

```nix
# gitea-prod.nix
{ config, pkgs, lib, ... }:

{
  imports = [ ./modules/gitea/server.nix ];

  services.gitea = {
    enable = true;
    database = {
      type = "postgres";
      host = "postgres.quadnix.internal";
      name = "gitea";
      user = "gitea";
    };
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeysOnly = true;
    };
    backup = {
      enable = true;
      interval = "daily";
      retention = 30;
    };
  };
}
```

## Benefits

1. **Consistency**: Single declarative source for all service configs
2. **Reproducibility**: Identical deployments across environments
3. **Maintainability**: Centralized option definitions
4. **Version Control**: Config changes tracked in version control
5. **Testing**: Module tests validate configuration before deployment
6. **Rollback**: Easy reversion to previous configurations

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Migration complexity | High | Phased rollout with staging validation |
| Breaking changes | Medium | Maintain backward compatibility |
| Team learning curve | Low | Documentation and training sessions |
| Performance overhead | Low | Profile-based optimizations |

## Success Criteria

- [ ] All Kubernetes control-plane services managed through Nix modules
- [ ] Gitea service fully configured via `services.gitea` module
- [ ] Zero manual configuration files in production
- [ ] Automated testing pipeline for configuration validation
- [ ] Documented migration and upgrade procedures

## References

- [NixOS Module System](https://nixos.org/manual/nixos/stable/#sec-module-system)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Gitea Configuration](https://docs.gitea.io/en-us/config-cheat-sheet/)
