# QuadNix Helm Charts

Pre-configured Helm charts for the QuadNix infrastructure.

## Available Charts

### GitOps & CI/CD

#### ArgoCD
- **Namespace**: `argocd`
- **Features**: HA with Redis HA, ingress, server replicas
- **Access**: `helmCharts.argocd`

### Monitoring & Observability

#### Prometheus Stack
- **Namespace**: `monitoring`
- **Features**: Prometheus, Grafana, Alertmanager, node-exporter
- **Storage**: 50Gi for Prometheus, 10Gi for Grafana
- **Access**: `helmCharts.prometheus`

#### Grafana
- **Namespace**: `grafana`
- **Features**: Standalone Grafana with PostgreSQL backend
- **Datasources**: Prometheus, Loki, ClickHouse pre-configured
- **Plugins**: Clock, Pie Chart, World Map, ClickHouse
- **Access**: `helmCharts.grafana`

#### Loki
- **Namespace**: `loki`
- **Features**: Log aggregation with simple scalable deployment
- **Storage**: 50Gi for backend and write components
- **Access**: `helmCharts.loki`

#### Tempo
- **Namespace**: `tempo`
- **Features**: Distributed tracing, Jaeger & OTLP receivers
- **Storage**: 30Gi for traces
- **Access**: `helmCharts.tempo`

### Development Tools

#### Gitea
- **Namespace**: `gitea`
- **Features**: Git service with PostgreSQL & Redis
- **Components**: 
  - HTTP service on port 3000
  - SSH on port 2222 (LoadBalancer)
  - Actions enabled
- **Storage**: 50Gi for git data, 20Gi for PostgreSQL
- **Access**: `helmCharts.gitea`
- **URL**: https://gitea.quadtech.dev

### Databases & Analytics

#### ClickHouse
- **Namespace**: `clickhouse`
- **Features**: Clustered deployment with 2 shards, 2 replicas per shard
- **Components**: ZooKeeper for coordination
- **Storage**: 100Gi per instance, 10Gi for ZooKeeper
- **Ports**: HTTP (8123), TCP (9000), Interserver (9009)
- **Access**: `helmCharts.clickhouse`
- **URL**: https://clickhouse.quadtech.dev

#### ClickHouse Operator
- **Namespace**: `clickhouse-operator`
- **Features**: Manages ClickHouse clusters, metrics exporter
- **Access**: `helmCharts.clickhouse-operator`

### Networking & Security

#### Ingress-NGINX
- **Namespace**: `ingress-nginx`
- **Features**: Auto-scaling (2-5 replicas), metrics, PDB
- **Access**: `helmCharts.ingress-nginx`

#### Cert-Manager
- **Namespace**: `cert-manager`
- **Features**: Automatic TLS certificates, CRDs included
- **Access**: `helmCharts.cert-manager`

## Usage Examples

### Build Individual Charts

```sh
# Build Gitea chart
nix build .#chartsDerivations.x86_64-linux.gitea-charts.gitea

# Build ClickHouse chart
nix build .#chartsDerivations.x86_64-linux.clickhouse.clickhouse

# Build Grafana chart
nix build .#chartsDerivations.x86_64-linux.grafana.grafana
```

### Use Pre-configured Charts

```nix
{ inputs, pkgs, ... }:

let
  helmCharts = inputs.self.helmCharts.${pkgs.system};
in
{
  # Deploy all monitoring stack
  environment.systemPackages = [
    helmCharts.grafana
    helmCharts.loki
    helmCharts.tempo
  ];
}
```

### Custom Configuration

```nix
let
  helmLib = inputs.self.helmLib.x86_64-linux;
  
  customGitea = helmLib.buildChart {
    name = "gitea";
    chart = helmLib.charts.gitea-charts.gitea;
    namespace = "gitea";
    values = {
      replicaCount = 3;
      gitea.config.server.DOMAIN = "git.example.com";
      # ... your custom values
    };
  };
in
{
  environment.systemPackages = [ customGitea ];
}
```

## Chart Repository URLs

The following chart repositories are tracked:

- **Gitea**: https://dl.gitea.com/charts
- **ClickHouse**: https://docs.altinity.com/clickhouse-operator
- **Grafana**: https://grafana.github.io/helm-charts
- **Prometheus**: https://prometheus-community.github.io/helm-charts
- **ArgoCD**: https://argoproj.github.io/argo-helm
- **Bitnami**: https://charts.bitnami.com/bitnami
- **Jetstack**: https://charts.jetstack.io
- **Ingress-NGINX**: https://kubernetes.github.io/ingress-nginx

## Security Notes

### Credentials Management

All charts use placeholder passwords (`changeme`). In production:

1. **Use SOPS for secrets**:
   ```nix
   sops.secrets."gitea-admin-password" = {
     sopsFile = ../secrets/gitea.yaml;
   };
   ```

2. **Override with Kubernetes secrets**:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: gitea-admin
   stringData:
     password: <actual-password>
   ```

3. **Use Sealed Secrets or External Secrets Operator**

### Required Secrets

- **Gitea**: admin password, PostgreSQL password
- **ClickHouse**: admin password, ZooKeeper credentials
- **Grafana**: admin password, PostgreSQL password, secret key
- **PostgreSQL** (all): database passwords

## Deployment Workflow

### 1. Update Charts

```sh
nix flake update nixhelm
```

### 2. Build Desired Charts

```sh
nix build .#helmCharts.x86_64-linux.all.gitea
nix build .#helmCharts.x86_64-linux.all.clickhouse
nix build .#helmCharts.x86_64-linux.all.grafana
```

### 3. Deploy to Kubernetes

```sh
# Using Helm
helm install gitea ./result/*.tgz -n gitea --create-namespace

# Using kubectl
helm template gitea ./result/*.tgz -n gitea | kubectl apply -f -

# Using ArgoCD
# Commit manifests to git and create ArgoCD Application
```

### 4. Verify Deployment

```sh
kubectl get pods -n gitea
kubectl get pods -n clickhouse
kubectl get pods -n grafana
```

## Integration with Existing Services

These charts integrate with QuadNix's existing services:

- **services/gitea.nix** → Migrate to `helmCharts.gitea`
- **services/clickhouse.nix** → Migrate to `helmCharts.clickhouse`
- **profiles/kubernetes/helm.nix** → Already configured

## High Availability Configuration

All charts include HA configurations:

- **Multiple replicas** for stateless components
- **Pod anti-affinity** to spread across nodes
- **Pod Disruption Budgets** to prevent complete outages
- **Persistent volumes** for stateful data
- **Health checks** (liveness/readiness probes)

## Resource Requirements

Minimum cluster requirements for all charts:

- **CPU**: ~12 cores
- **Memory**: ~32 GB RAM
- **Storage**: ~500 GB
- **Nodes**: 3+ for proper HA distribution

Individual chart requirements are documented in each chart file.

## Monitoring

Charts with monitoring enabled:

- ✅ Prometheus (self-monitoring)
- ✅ Grafana (metrics endpoint)
- ✅ ClickHouse (ServiceMonitor)
- ✅ Ingress-NGINX (ServiceMonitor)
- ✅ Loki (ServiceMonitor)
- ✅ Tempo (ServiceMonitor)
- ✅ ClickHouse Operator (metrics exporter)

## Further Reading

- [QUICKSTART.md](./QUICKSTART.md) - Get started quickly
- [README.md](./README.md) - Full documentation
- [INTEGRATION.md](./INTEGRATION.md) - Integration details
- Chart configurations in `lib/helm/charts/`

## Support

For issues or questions:
1. Check the chart's default values in nixhelm
2. Review the chart documentation at the repository URL
3. See `lib/helm/charts/<chart>.nix` for configuration details
