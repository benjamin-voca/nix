# QuadNix - NixOS Infrastructure

## Overview

QuadNix is a NixOS infrastructure-as-code project using flakes for declarative system configuration. The project manages a Kubernetes cluster with control plane and worker nodes, along with supporting services like Gitea, Buildkite, OpenTelemetry, and ClickHouse.

## Tech Stack

- **Language**: Nix (domain-specific language for system configuration)
- **Framework**: NixOS with flakes for reproducible builds
- **Container Orchestration**: Kubernetes (control-plane + workers)
- **Deployment**: deploy-rs for atomic deployments
- **Secrets Management**: SOPS-Nix with age encryption
- **Services**: Gitea, Buildkite, OpenTelemetry Collector, ClickHouse, PostgreSQL (Crunchy)

## Architecture

### Directory Structure

```
├── hosts/           # Host-specific configurations
├── roles/           # Role compositions (backbone, frontline)
├── profiles/        # Reusable configuration modules
├── services/        # Service definitions
├── lib/             # Custom library functions
├── secrets/         # Encrypted secrets (SOPS)
└── flake.nix        # Flake entry point
```

### Host Naming Convention

- **backbone-##**: Control plane nodes (e.g., backbone-01, backbone-02)
- **frontline-##**: Worker nodes running workloads (e.g., frontline-01, frontline-02)

### Core Concepts

- **Host**: A machine running NixOS
- **Role**: Functional classification (backbone = control plane, frontline = worker)
- **Profile**: Reusable configuration module
- **Service**: Software application deployment
- **HA**: High Availability configuration

## Key Patterns

1. **Host Configuration Pattern**: Per-host configuration files that import roles
2. **Role Composition Pattern**: Combining profiles into role-based configurations
3. **Profile Structure Pattern**: Reusable module organization
4. **Service Module Pattern**: Encapsulated service definitions
5. **Hardware Configuration Pattern**: Per-host hardware specifications
6. **Flake Pattern**: Centralized input/output management
