# Backbone Services - Kubernetes Manifests
#
# This directory contains Kubernetes manifests for internal infrastructure services
# that run on backbone nodes.
#
# Services:
# - forgejo/          Git service with PostgreSQL and Redis
# - clickhouse/     Analytics and logging database
# - grafana/        Observability dashboard with Loki and Tempo
# - prometheus/     Monitoring stack
# - ingress-nginx/  Ingress controller for routing
# - cert-manager/   TLS certificate management
#
# These manifests are generated from the Helm charts defined in lib/helm/charts/

## Deployment Order

1. **Infrastructure** (deploy first):
   ```sh
   kubectl apply -f ingress-nginx/
   kubectl apply -f cert-manager/
   ```

2. **Monitoring** (deploy second):
   ```sh
   kubectl apply -f prometheus/
   kubectl apply -f grafana/
   ```

3. **Services** (deploy third):
   ```sh
   kubectl apply -f forgejo/
   kubectl apply -f clickhouse/
   ```

## Building Manifests from Helm Charts

To rebuild manifests from the Helm charts:

```sh
# Build the chart
nix build .#helmCharts.x86_64-linux.all.forgejo

# Template to YAML
helm template forgejo ./result/*.tgz -n forgejo > manifests/backbone/forgejo/deployment.yaml

# Apply to cluster
kubectl apply -f manifests/backbone/forgejo/
```

## Manual Deployment

If you prefer to use Helm directly:

```sh
# Install from built chart
nix build .#chartsDerivations.x86_64-linux.forgejo-charts.forgejo
helm install forgejo ./result/*.tgz -n forgejo --create-namespace
```

## Automatic Deployment with ArgoCD

For GitOps workflow, use ArgoCD to watch this repository and auto-deploy changes.

See `manifests/backbone/argocd/` for ArgoCD setup.
