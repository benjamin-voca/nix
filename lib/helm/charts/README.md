# Nix-built Helm Charts Integration

This directory contains Nix flakes for building reproducible Helm charts for QuadNix services.

## Available Charts

### ArgoCD
- **Version**: 6.7.2
- **Source**: Upstream ArgoCD Helm chart
- **Purpose**: GitOps continuous delivery for Kubernetes

### Gitea
- **Version**: 4.4.0
- **Source**: Official Gitea Helm chart
- **Purpose**: Git repository hosting and CI/CD platform

## Building Charts

### Local Build
```bash
nix build .#argocd  # Builds ArgoCD chart
nix build .#gitea   # Builds Gitea chart
```

### Output
Built charts are packaged as `.tgz` files in the output directory.

## CI Integration

Charts are automatically built and published via Gitea Actions when changes are pushed to the repository.

## Chart Customization

Charts can be customized by:
- Overriding values in the Nix flake
- Adding custom templates
- Modifying chart dependencies

## Version Management

Update chart versions in the flake.nix file to trigger new builds and deployments via ArgoCD.