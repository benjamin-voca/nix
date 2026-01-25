# Helm Charts Integration

This project integrates [nixhelm](https://github.com/farcaller/nixhelm) and [nix-kube-generators](https://github.com/farcaller/nix-kube-generators) to provide a declarative way to manage Helm charts in NixOS.

## Overview

The Helm integration provides:

- **Direct access to nixhelm charts**: All charts from nixhelm repositories
- **Pre-configured charts**: Ready-to-use configurations for common applications
- **Helm chart builder**: Utilities to build and customize Helm charts
- **GitOps integration**: Support for ArgoCD and other GitOps tools

## Directory Structure

```
lib/helm/
├── default.nix          # Main helm library
├── utils.nix            # Utility functions for helm charts
├── repositories.nix     # Chart repository definitions
└── charts/              # Pre-configured chart definitions
    ├── default.nix      # Index of all charts
    ├── argocd.nix       # ArgoCD configuration
    ├── prometheus.nix   # Prometheus/Grafana stack
    └── ingress.nix      # Ingress-nginx and cert-manager
```

## Quick Start

### 1. Building a Chart from nixhelm

Access any chart from the nixhelm repository:

```nix
# flake.nix or any nix file
let
  # Get a specific chart derivation
  argocdChart = inputs.self.chartsDerivations.x86_64-linux.argoproj.argo-cd;
in
{
  # Use in your configuration
  environment.systemPackages = [ argocdChart ];
}
```

Build a chart directly:

```sh
# Build ArgoCD chart
nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd

# Result will be in ./result/
```

### 2. Using Pre-configured Charts

The project includes pre-configured charts for common applications:

```nix
# In your NixOS configuration
{ inputs, ... }:

let
  helmCharts = inputs.self.helmCharts.x86_64-linux;
in
{
  # Deploy ArgoCD
  environment.systemPackages = [ helmCharts.argocd ];
}
```

### 3. Creating Custom Chart Configurations

Use the helm library to create custom chart configurations:

```nix
{ inputs, ... }:

let
  helmLib = inputs.self.helmLib.x86_64-linux;
  
  myChart = helmLib.buildChart {
    name = "my-app";
    chart = helmLib.charts.bitnami.nginx;
    namespace = "my-namespace";
    values = {
      replicaCount = 3;
      service = {
        type = "LoadBalancer";
      };
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
      };
    };
  };
in
{
  environment.systemPackages = [ myChart ];
}
```

## Available Charts

### From nixhelm

All charts from nixhelm are available through the `chartsDerivations` output:

```nix
inputs.self.chartsDerivations.${system}.${repo}.${chart}
```

Example repositories:
- `argoproj` - ArgoCD, Argo Workflows, Argo Events
- `prometheus-community` - Prometheus, Grafana, Alertmanager
- `bitnami` - PostgreSQL, Redis, NGINX, etc.
- `jetstack` - cert-manager
- `ingress-nginx` - NGINX Ingress Controller

### Pre-configured Charts

Access through `helmCharts` output:

- `argocd` - ArgoCD with HA configuration
- `prometheus` - Complete Prometheus/Grafana stack
- `ingress-nginx` - NGINX Ingress Controller with auto-scaling
- `cert-manager` - Cert-manager with CRDs installed

## Advanced Usage

### Building Multiple Charts

```nix
let
  helmLib = inputs.self.helmLib.x86_64-linux;
  
  charts = helmLib.buildCharts [
    {
      name = "app1";
      chart = helmLib.charts.bitnami.nginx;
      namespace = "app1";
      values = { /* ... */ };
    }
    {
      name = "app2";
      chart = helmLib.charts.bitnami.redis;
      namespace = "app2";
      values = { /* ... */ };
    }
  ];
in
charts
```

### Using Utility Functions

The `lib/helm/utils.nix` provides helpful utilities:

```nix
let
  helmUtils = import ./lib/helm/utils.nix { inherit pkgs; };
in
{
  # Merge multiple value sets
  mergedValues = helmUtils.mergeValues [
    { replicas = 2; }
    { service.type = "LoadBalancer"; }
  ];

  # Create namespace manifest
  namespace = helmUtils.mkNamespace "my-app";

  # Create common values with defaults
  commonValues = helmUtils.mkCommonValues {
    namespace = "my-app";
    replicas = 3;
    resources = {
      requests.cpu = "500m";
    };
  };

  # Create ArgoCD Application manifest
  argoApp = helmUtils.mkArgoApplication {
    name = "my-app";
    namespace = "argocd";
    repoURL = "https://github.com/myorg/myrepo";
    path = "charts/my-app";
  };
}
```

### OCI Registry Support

nixhelm supports OCI-compliant registries:

```sh
# Add an OCI chart to nixhelm (upstream contribution)
nix run github:farcaller/nixhelm#helmupdater -- init \
  "oci://ghcr.io/myorg/charts" \
  myorg/nginx \
  --commit
```

## Using with ArgoCD

For GitOps workflows with ArgoCD:

1. Build your charts as shown above
2. Commit the rendered manifests to your git repository
3. Create an ArgoCD Application pointing to your manifests

Or use [cake](https://github.com/farcaller/cake) for full ArgoCD integration.

## Adding New Charts

### From nixhelm (Recommended for Public Charts)

Contribute to nixhelm upstream:

```sh
# Clone nixhelm
git clone https://github.com/farcaller/nixhelm
cd nixhelm

# Add a new chart
nix run .#helmupdater -- init \
  "https://prometheus-community.github.io/helm-charts" \
  prometheus-community/prometheus \
  --commit

# Submit PR to nixhelm
```

### Local Charts

For private or local charts, create a new file in `lib/helm/charts/`:

```nix
# lib/helm/charts/my-custom-chart.nix
{ helmLib }:

{
  my-app = helmLib.buildChart {
    name = "my-app";
    chart = helmLib.charts.myrepo.mychart;
    namespace = "my-namespace";
    values = {
      # Your values here
    };
  };
}
```

Then add it to `lib/helm/charts/default.nix`:

```nix
let
  myCustomChart = import ./my-custom-chart.nix { inherit helmLib; };
in
{
  inherit (myCustomChart) my-app;
  
  all = {
    inherit (myCustomChart) my-app;
    # ... existing charts
  };
}
```

## Caching

nixhelm provides a public Cachix cache to speed up builds:

```sh
# Enable the cache
cachix use nixhelm
```

Or manually add to `/etc/nix/nix.conf`:

```nix
substituters = https://cache.nixos.org https://nixhelm.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY=
```

## Troubleshooting

### Chart not found

If a chart isn't available in nixhelm:

1. Check if it exists in nixhelm: `nix eval .#chartsMetadata --apply builtins.attrNames`
2. Add it to nixhelm upstream (see "Adding New Charts")
3. Use a local git repository as a flake input

### Values not applying

Ensure your values structure matches the chart's `values.yaml`:

```sh
# Download and inspect the chart
nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd
tar -xzf result/*.tgz
cat argo-cd/values.yaml
```

### Build errors

Check the nixhelm and nix-kube-generators versions in `flake.lock`:

```sh
nix flake update nixhelm nix-kube-generators
```

## Examples

See the pre-configured charts in `lib/helm/charts/` for complete examples:

- `argocd.nix` - Production-ready ArgoCD with HA
- `prometheus.nix` - Complete monitoring stack with Grafana
- `ingress.nix` - Ingress controller with cert-manager

## References

- [nixhelm](https://github.com/farcaller/nixhelm) - Helm charts in Nix
- [nix-kube-generators](https://github.com/farcaller/nix-kube-generators) - Kubernetes manifest generators
- [cake](https://github.com/farcaller/cake) - ArgoCD integration
- [Helm](https://helm.sh/) - The package manager for Kubernetes

## License

This integration follows the same license as the main project. nixhelm is Apache-2.0 licensed.
