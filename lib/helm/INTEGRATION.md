# nixhelm Integration Summary

## What Was Added

This integration adds comprehensive Helm chart management capabilities to QuadNix using nixhelm and nix-kube-generators.

## Files Created

```
lib/helm/
├── README.md                    # Complete documentation
├── QUICKSTART.md               # Quick start guide
├── default.nix                 # Main helm library
├── utils.nix                   # Utility functions
├── repositories.nix            # Repository configuration
├── charts/                     # Pre-configured charts
│   ├── default.nix            # Chart index
│   ├── argocd.nix             # ArgoCD configuration
│   ├── prometheus.nix         # Prometheus/Grafana stack
│   └── ingress.nix            # Ingress-nginx + cert-manager
└── examples/
    └── argocd-service.nix     # NixOS service example

scripts/
└── test-helm.sh               # Integration test script
```

## Files Modified

- `flake.nix` - Added nixhelm and nix-kube-generators inputs
- `README.md` - Added Helm charts section

## New Flake Outputs

### `helmLib.${system}`

The helm library with chart builder functions:

```nix
{
  kubelib           # nix-kube-generators library
  charts            # All nixhelm charts
  buildChart        # Function to build a single chart
  buildCharts       # Function to build multiple charts
  buildHelmChart    # Direct access to kubelib.buildHelmChart
}
```

### `helmCharts.${system}`

Pre-configured charts ready to use:

```nix
{
  argocd           # ArgoCD with HA configuration
  prometheus       # Prometheus + Grafana + Alertmanager
  ingress-nginx    # NGINX Ingress with auto-scaling
  cert-manager     # Cert-manager with CRDs
  all              # All charts in one attribute set
}
```

### `chartsDerivations`

Direct access to nixhelm chart derivations:

```
chartsDerivations.${system}.${repo}.${chart}
```

Examples:
- `.x86_64-linux.argoproj.argo-cd`
- `.x86_64-linux.prometheus-community.kube-prometheus-stack`
- `.x86_64-linux.bitnami.postgresql`

### `chartsMetadata`

Chart metadata from nixhelm:

```
chartsMetadata.${repo}.${chart}
```

## Key Features

### 1. Direct Chart Access

Build any chart from nixhelm repositories:

```sh
nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd
```

### 2. Declarative Configuration

Configure charts in Nix:

```nix
helmLib.buildChart {
  name = "myapp";
  chart = helmLib.charts.bitnami.nginx;
  namespace = "myapp";
  values = {
    replicaCount = 3;
    service.type = "LoadBalancer";
  };
}
```

### 3. Pre-configured Charts

Production-ready configurations included for:
- ArgoCD (GitOps platform)
- Prometheus/Grafana (Monitoring stack)
- Ingress-NGINX (Ingress controller)
- Cert-manager (Certificate management)

### 4. Utility Functions

Helper functions for common tasks:
- `mergeValues` - Merge multiple value sets
- `toYAML` - Convert Nix to YAML
- `mkNamespace` - Create namespace manifests
- `mkCommonValues` - Standard resource configurations
- `mkArgoApplication` - ArgoCD Application manifests
- `validateValues` - Validate required values

### 5. Repository Management

Track chart repositories in `repositories.nix`:
- HTTP/HTTPS repositories (traditional Helm repos)
- OCI registries (ghcr.io, Docker Hub, etc.)

### 6. NixOS Integration

Example NixOS service showing how to integrate charts into system configurations.

## Usage Examples

### Basic: Build a Chart

```sh
nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd
```

### Advanced: Custom Configuration

```nix
let
  helmLib = inputs.self.helmLib.x86_64-linux;
in
helmLib.buildChart {
  name = "argocd";
  chart = helmLib.charts.argoproj.argo-cd;
  namespace = "argocd";
  values = {
    server.replicas = 2;
    redis-ha.enabled = true;
  };
}
```

### NixOS Service

```nix
{ inputs, pkgs, ... }:

let
  helmCharts = inputs.self.helmCharts.${pkgs.system};
in
{
  environment.systemPackages = [ helmCharts.argocd ];
}
```

## Supported Repositories

Pre-configured repositories (via nixhelm):
- `argoproj` - ArgoCD, Argo Workflows, Argo Events
- `prometheus-community` - Prometheus, Grafana, Alertmanager
- `bitnami` - PostgreSQL, Redis, NGINX, and more
- `jetstack` - cert-manager
- `ingress-nginx` - NGINX Ingress Controller

## Testing

Run the integration test:

```sh
./scripts/test-helm.sh
```

## Documentation

- **Full Guide**: `lib/helm/README.md`
- **Quick Start**: `lib/helm/QUICKSTART.md`
- **Examples**: `lib/helm/charts/` and `lib/helm/examples/`

## Benefits

1. **Declarative**: Manage Helm charts in Nix configuration
2. **Reproducible**: Lock chart versions with flake.lock
3. **Type-safe**: Nix validates configuration at build time
4. **Cached**: Use nixhelm Cachix cache for fast builds
5. **GitOps-ready**: Works with ArgoCD and other GitOps tools
6. **No runtime dependencies**: Charts are built at evaluation time

## Next Steps

1. Enable nixhelm Cachix cache: `cachix use nixhelm`
2. Update charts: `nix flake update nixhelm`
3. Explore pre-configured charts in `lib/helm/charts/`
4. Create your own chart configurations
5. Integrate with your Kubernetes cluster

## Resources

- [nixhelm](https://github.com/farcaller/nixhelm)
- [nix-kube-generators](https://github.com/farcaller/nix-kube-generators)
- [cake](https://github.com/farcaller/cake) - ArgoCD integration
- [Helm](https://helm.sh/)

## License

This integration maintains compatibility with:
- QuadNix project license
- nixhelm: Apache-2.0
- nix-kube-generators: MIT
