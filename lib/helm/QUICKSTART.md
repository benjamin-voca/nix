# Helm Charts Quick Start

This guide will get you up and running with nixhelm in this project.

## Prerequisites

1. Nix with flakes enabled
2. Optional: Cachix for faster builds (`cachix use nixhelm`)

## 1. Update Dependencies

First, fetch the latest nixhelm charts:

```sh
nix flake update
```

## 2. Browse Available Charts

List all available chart repositories:

```sh
nix eval .#chartsMetadata --apply 'md: builtins.attrNames md'
```

Example repositories you'll see:
- `argoproj` - ArgoCD, Argo Workflows, Argo Events
- `prometheus-community` - Prometheus, Grafana
- `bitnami` - PostgreSQL, Redis, NGINX
- `jetstack` - cert-manager
- `ingress-nginx` - NGINX Ingress Controller

## 3. Build a Chart

Build the ArgoCD Helm chart:

```sh
nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd
```

The chart will be in `./result/`:

```sh
ls -la result/
# Contains the .tgz chart file
```

## 4. Use Pre-configured Charts

Check available pre-configured charts:

```sh
nix eval .#helmCharts.x86_64-linux --apply 'charts: builtins.attrNames charts.all'
```

These charts come with production-ready configurations. See examples in `lib/helm/charts/`.

## 5. Create a Custom Chart Configuration

Create a file `lib/helm/charts/mychart.nix`:

```nix
{ helmLib }:

{
  myapp = helmLib.buildChart {
    name = "myapp";
    chart = helmLib.charts.bitnami.nginx;  # Use any chart from nixhelm
    namespace = "myapp";
    values = {
      # Your Helm values here
      replicaCount = 3;
      service = {
        type = "LoadBalancer";
        port = 80;
      };
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
        limits = {
          cpu = "500m";
          memory = "512Mi";
        };
      };
    };
  };
}
```

Add it to `lib/helm/charts/default.nix`:

```nix
let
  # ... existing imports ...
  mychart = import ./mychart.nix { inherit helmLib; };
in
{
  # ... existing exports ...
  inherit (mychart) myapp;
  
  all = {
    # ... existing charts ...
    inherit (mychart) myapp;
  };
}
```

## 6. Use in NixOS Configuration

In your NixOS configuration (e.g., `services/myapp.nix`):

```nix
{ config, pkgs, inputs, ... }:

let
  helmLib = inputs.self.helmLib.${pkgs.system};
  
  myappChart = helmLib.buildChart {
    name = "myapp";
    chart = helmLib.charts.bitnami.nginx;
    namespace = "myapp";
    values = {
      # ... your values ...
    };
  };
in
{
  environment.systemPackages = [ myappChart ];
}
```

## 7. Deploy with kubectl

After building a chart, you can deploy it to your cluster:

```sh
# Build the chart
nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd

# Install with Helm
helm install argocd ./result/*.tgz -n argocd --create-namespace

# Or use kubectl with rendered manifests
helm template argocd ./result/*.tgz -n argocd | kubectl apply -f -
```

## Common Workflows

### Update All Charts

```sh
nix flake update nixhelm
```

### Add a New Chart Repository

Contribute to nixhelm upstream:

```sh
git clone https://github.com/farcaller/nixhelm
cd nixhelm

# Add a chart
nix run .#helmupdater -- init \
  "https://prometheus-community.github.io/helm-charts" \
  prometheus-community/prometheus \
  --commit

# Submit a PR
```

### Test Chart Configuration

Use `helm template` to see the rendered manifests without deploying:

```sh
nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd
helm template test-release ./result/*.tgz --debug
```

### Use with ArgoCD

1. Build your charts
2. Commit rendered manifests to git
3. Create ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/yourorg/yourrepo
    path: charts/myapp
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
```

## Troubleshooting

### "Chart not found" error

The chart might not be in nixhelm yet. Options:
1. Add it to nixhelm (recommended)
2. Use a git repository as a flake input
3. Build the chart locally

### Build taking too long

Enable the nixhelm Cachix cache:

```sh
cachix use nixhelm
```

### Values not applying correctly

Check the chart's default values:

```sh
nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd
tar -xzf result/*.tgz
cat argo-cd/values.yaml
```

## Next Steps

- Read the full documentation: `lib/helm/README.md`
- Check example configurations: `lib/helm/charts/`
- See the service example: `lib/helm/examples/argocd-service.nix`
- Visit [nixhelm repository](https://github.com/farcaller/nixhelm)

## Testing

Run the test script:

```sh
./scripts/test-helm.sh
```

This verifies the integration is working correctly.
