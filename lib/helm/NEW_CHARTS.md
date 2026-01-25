# New Charts Added - Summary

## Overview

Added production-ready Helm chart configurations for Gitea, ClickHouse, and Grafana (with Loki and Tempo) to the QuadNix project.

## Files Created

### Chart Configurations

1. **lib/helm/charts/gitea.nix** (206 lines)
   - Gitea git service with HA
   - PostgreSQL database
   - Redis caching
   - SSH and HTTP services
   - Ingress with TLS

2. **lib/helm/charts/clickhouse.nix** (280 lines)
   - ClickHouse clustered deployment (2 shards × 2 replicas)
   - ZooKeeper for coordination
   - ClickHouse Operator for cluster management
   - Monitoring with ServiceMonitor
   - HTTP and TCP interfaces

3. **lib/helm/charts/grafana.nix** (426 lines)
   - Standalone Grafana with PostgreSQL
   - Loki for log aggregation
   - Tempo for distributed tracing
   - Pre-configured datasources (Prometheus, Loki, ClickHouse)
   - Dashboard providers and sidecar
   - ClickHouse plugin included

### Documentation

4. **lib/helm/CHARTS.md**
   - Comprehensive guide for all available charts
   - Usage examples for each chart
   - Security notes and credential management
   - Deployment workflows
   - HA configuration details

## Files Modified

1. **lib/helm/repositories.nix**
   - Added `gitea-charts` repository (https://dl.gitea.com/charts)
   - Added `clickhouse` repository (https://docs.altinity.com/clickhouse-operator)
   - Added `grafana` repository (https://grafana.github.io/helm-charts)

2. **lib/helm/charts/default.nix**
   - Imported new chart modules
   - Exported: `gitea`, `clickhouse`, `clickhouse-operator`, `grafana`, `loki`, `tempo`
   - Updated `all` attribute set

## Chart Details

### Gitea (Git Service)

**Configuration Highlights:**
- 2 replicas for HA
- PostgreSQL database (20Gi storage)
- Redis cluster for caching/sessions/queues
- SSH service (LoadBalancer on port 2222)
- HTTP service with ingress (git.quadtech.dev)
- Gitea Actions enabled
- 50Gi persistent storage for repositories
- Pod anti-affinity for node distribution

**Access:**
```nix
helmCharts.gitea
# or
helmLib.charts.gitea-charts.gitea
```

### ClickHouse (Analytics Database)

**Configuration Highlights:**
- **Main Chart**: Clustered ClickHouse (2 shards, 2 replicas per shard)
  - 100Gi storage per instance
  - ZooKeeper ensemble (3 replicas, 10Gi each)
  - HTTP (8123), TCP (9000), Interserver (9009) ports
  - Distributed DDL support
  - Compression with zstd
  - Admin and default users

- **Operator Chart**: ClickHouse Operator
  - 2 replicas for HA
  - Metrics exporter on port 8888
  - Webhook support
  - RBAC and ServiceAccount

**Access:**
```nix
helmCharts.clickhouse
helmCharts.clickhouse-operator
# or
helmLib.charts.clickhouse.clickhouse
helmLib.charts.clickhouse.clickhouse-operator
```

### Grafana Stack (Observability)

**Configuration Highlights:**

- **Grafana**: Standalone deployment
  - 2 replicas for HA
  - PostgreSQL backend (5Gi)
  - 10Gi persistent storage
  - Pre-configured datasources:
    - Prometheus (default)
    - Loki (logs)
    - ClickHouse (analytics)
  - Plugins: Clock, Pie Chart, World Map, ClickHouse
  - Dashboard sidecar for auto-loading
  - ServiceMonitor for Prometheus

- **Loki**: Log aggregation
  - SimpleScalable deployment mode
  - 2 replicas each for backend, read, write
  - 50Gi storage for backend and write
  - Gateway with 2 replicas
  - TSDB schema (v12)

- **Tempo**: Distributed tracing
  - 2 replicas
  - 30Gi storage for traces
  - Jaeger receivers (gRPC 14250, HTTP 14268)
  - OTLP receivers (gRPC 4317, HTTP 4318)

**Access:**
```nix
helmCharts.grafana
helmCharts.loki
helmCharts.tempo
# or
helmLib.charts.grafana.grafana
helmLib.charts.grafana.loki
helmLib.charts.grafana.tempo
```

## Usage Examples

### Build Charts

```sh
# Gitea
nix build .#chartsDerivations.x86_64-linux.gitea-charts.gitea

# ClickHouse
nix build .#chartsDerivations.x86_64-linux.clickhouse.clickhouse
nix build .#chartsDerivations.x86_64-linux.clickhouse.clickhouse-operator

# Grafana stack
nix build .#chartsDerivations.x86_64-linux.grafana.grafana
nix build .#chartsDerivations.x86_64-linux.grafana.loki
nix build .#chartsDerivations.x86_64-linux.grafana.tempo
```

### Use Pre-configured Charts

```nix
{ inputs, pkgs, ... }:

let
  helmCharts = inputs.self.helmCharts.${pkgs.system};
in
{
  environment.systemPackages = [
    # Development
    helmCharts.gitea
    
    # Analytics
    helmCharts.clickhouse
    helmCharts.clickhouse-operator
    
    # Observability
    helmCharts.grafana
    helmCharts.loki
    helmCharts.tempo
  ];
}
```

### List All Available Charts

```sh
nix eval .#helmCharts.x86_64-linux --apply 'charts: builtins.attrNames charts.all'
```

Expected output:
```
[
  "argocd"
  "cert-manager"
  "clickhouse"
  "clickhouse-operator"
  "gitea"
  "grafana"
  "ingress-nginx"
  "loki"
  "prometheus"
  "tempo"
]
```

## Integration with Existing Services

These charts can replace/enhance existing QuadNix services:

### Gitea
**Current**: `services/gitea.nix` uses NixOS service
**New**: `helmCharts.gitea` provides Kubernetes deployment with HA

### ClickHouse
**Current**: `services/clickhouse.nix` uses NixOS service
**New**: `helmCharts.clickhouse` provides clustered deployment

### Grafana
**Current**: Part of `helmCharts.prometheus` (kube-prometheus-stack)
**New**: `helmCharts.grafana` provides standalone deployment with more control

## Security Considerations

All charts use placeholder passwords that MUST be changed:

### Required Secret Updates

1. **Gitea**
   - `gitea.admin.password`: Admin user password
   - `postgresql.auth.password`: PostgreSQL password

2. **ClickHouse**
   - `clickhouseConfig.users.admin.password`: Admin password

3. **Grafana**
   - `adminPassword`: Grafana admin password
   - `grafana.ini.security.secret_key`: Session secret key
   - `postgresql.auth.password`: PostgreSQL password

### Recommended: Use SOPS

```nix
sops.secrets."gitea/admin-password" = {
  sopsFile = ../secrets/gitea.yaml;
  key = "admin_password";
};
```

## Resource Requirements

Total resources for all new charts:

**Gitea:**
- CPU: 200m-2000m (request-limit)
- Memory: 512Mi-2Gi
- Storage: 70Gi (50Gi git + 20Gi PostgreSQL)

**ClickHouse:**
- CPU: 2000m-16000m (4 instances)
- Memory: 8Gi-32Gi
- Storage: 430Gi (400Gi data + 30Gi ZooKeeper)

**Grafana Stack:**
- CPU: 300m-3000m (request-limit)
- Memory: 768Mi-3Gi
- Storage: 145Gi (Grafana 15Gi + Loki 100Gi + Tempo 30Gi)

**Total Minimum:**
- CPU: ~3 cores (requests)
- Memory: ~10Gi
- Storage: ~645Gi

## High Availability Features

All charts include:
- ✅ Multiple replicas
- ✅ Pod anti-affinity (spread across nodes)
- ✅ Pod disruption budgets
- ✅ Health checks (liveness/readiness)
- ✅ Persistent storage
- ✅ Resource limits
- ✅ Security contexts

## Monitoring Integration

Charts with Prometheus monitoring:
- ✅ Gitea (metrics available)
- ✅ ClickHouse (ServiceMonitor)
- ✅ ClickHouse Operator (metrics exporter)
- ✅ Grafana (ServiceMonitor)
- ✅ Loki (ServiceMonitor)
- ✅ Tempo (ServiceMonitor)

All integrate with existing `helmCharts.prometheus` stack.

## Testing

Test the new charts:

```sh
./scripts/test-helm.sh
```

## Next Steps

1. **Update flake.lock**: `nix flake update nixhelm`
2. **Test builds**: Build individual charts
3. **Update secrets**: Replace placeholder passwords
4. **Deploy to cluster**: Use Helm or kubectl
5. **Configure monitoring**: Ensure ServiceMonitors are scraped
6. **Set up ingress**: Configure DNS for services

## Documentation

- **Chart Details**: `lib/helm/CHARTS.md`
- **Quick Start**: `lib/helm/QUICKSTART.md`
- **Full Guide**: `lib/helm/README.md`
- **Integration**: `lib/helm/INTEGRATION.md`

## Total Line Count

```
206  gitea.nix
280  clickhouse.nix
426  grafana.nix
----
912  total chart configuration lines
```

All charts are production-ready with comprehensive configurations for high availability, monitoring, and security.
