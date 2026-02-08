# Backbone Services Deployment Guide

This guide covers the deployment of critical backbone services with High Availability (HA) configuration, ensuring they run exclusively on backbone nodes and remain always available.

## Service Overview

### Core Backbone Services
- **ArgoCD**: GitOps continuous delivery (replicas: 2)
- **Gitea**: Git repository hosting (replicas: 2-3)
- **Grafana**: Monitoring dashboard (replicas: 3)
- **Loki**: Log aggregation (replicas: 3)
- **Tempo**: Distributed tracing (replicas: 3)
- **ClickHouse**: Time-series database (shards: 2, replicas: 2)
- **Verdaccio**: NPM registry (replicas: 2)

### Gitea Runners Distribution
- **Backbone runners**: 1-2 (on backbone nodes)
- **Frontline runners**: 2-3 (on frontline nodes)

## HA Configuration Patterns

### 1. Multi-Replica Deployments
Each service runs with multiple replicas for redundancy:
- **Minimum**: 2 replicas for critical services
- **Recommended**: 3 replicas for monitoring stack
- **ClickHouse**: 2 shards × 2 replicas = 4 total pods

### 2. Node Affinity
All backbone services are constrained to backbone nodes:
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: "role"
          operator: "In"
          values: [ "backbone" ]
```

### 3. Pod Disruption Budgets
Ensures minimum availability:
```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

### 4. Anti-Affinity
Spreads pods across different nodes:
```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: "app.kubernetes.io/name"
            operator: "In"
            values: [ "service-name" ]
        topologyKey: "kubernetes.io/hostname"
```

## Service-Specific HA Configurations

### ArgoCD
- **Replicas**: 2
- **Storage**: Persistent for application manifests
- **Health Checks**: Automatic sync with self-healing

### Gitea (Complete HA Setup)
- **Replicas**: 2-3
- **PostgreSQL**: 2 replicas (primary + standby)
- **Redis**: 2 replicas (master + slave)
- **Runners**: Distributed across backbone and frontline
- **Persistence**: 50Gi Longhorn storage

### Grafana
- **Replicas**: 3
- **PostgreSQL**: 2 replicas for dashboard storage
- **Plugins**: ClickHouse datasource included
- **ServiceMonitor**: Prometheus integration

### Loki
- **Replicas**: 3 (backend + read + write)
- **Storage**: 100Gi filesystem by default
- **Mode**: SimpleScalable for easy scaling
- **Monitoring**: Self-monitoring enabled

### Tempo
- **Replicas**: 3
- **Storage**: 50Gi local by default
- **Receivers**: Jaeger and OTLP protocols
- **Integration**: Works with Grafana Loki

### ClickHouse
- **Shards**: 2
- **Replicas per shard**: 2
- **ZooKeeper**: 3 replicas for coordination
- **Storage**: 100Gi per pod
- **Ingress**: HTTP interface for queries

### Verdaccio
- **Replicas**: 2
- **Storage**: Persistent volume for packages
- **Security**: Admin user with password management

## Gitea Runners Distribution Strategy

### Backbone Runners (Critical)
- **Purpose**: Build internal infrastructure
- **Labels**: `backbone, self-hosted`
- **Resources**: 1 CPU, 2GB RAM each
- **Affinity**: Only on backbone nodes

### Frontline Runners (Customer Workloads)
- **Purpose**: Build customer applications
- **Labels**: `frontline, self-hosted`
- **Resources**: 2 CPU, 4GB RAM each
- **Affinity**: Only on frontline nodes

## Deployment Commands

### Enable All Backbone Services
```bash
# Enable the backbone services module
config.services.quadnix.backbone-services.enable = true;

# Configure specific services if needed
config.services.quadnix.backbone-services.services = [
  "argocd"
  "gitea"
  "grafana"
  "loki"
  "tempo"
  "clickhouse"
  "verdaccio"
];

# Configure Gitea runners
config.services.quadnix.backbone-services.giteaRunners = 3;
```

### Service-Specific Configuration
```bash
# Gitea HA configuration
config.services.quadnix.gitea-deploy.enable = true;
config.services.quadnix.gitea-deploy.replicas = 3;
config.services.quadnix.gitea-deploy.postgres.enable = true;
config.services.quadnix.gitea-deploy.postgres.replicas = 2;
config.services.quadnix.gitea-deploy.redis.enable = true;
config.services.quadnix.gitea-deploy.redis.replicas = 2;

# Grafana HA configuration
config.services.quadnix.grafana-deploy.enable = true;
config.services.quadnix.grafana-deploy.replicas = 3;
config.services.quadnix.grafana-deploy.postgres.enable = true;
config.services.quadnix.grafana-deploy.postgres.replicas = 2;

# ClickHouse HA configuration
config.services.quadnix.clickhouse-deploy.enable = true;
config.services.quadnix.clickhouse-deploy.shards = 2;
config.services.quadnix.clickhouse-deploy.replicasPerShard = 2;
config.services.quadnix.clickhouse-deploy.zookeeper.enable = true;
config.services.quadnix.clickhouse-deploy.zookeeper.replicas = 3;
```

## Monitoring and Health Checks

### Prometheus Integration
Each service includes:
- **ServiceMonitor**: For Prometheus scraping
- **Health Checks**: Liveness and readiness probes
- **Resource Limits**: CPU and memory constraints

### Health Check Endpoints
- **Gitea**: `/healthz`
- **Grafana**: `/api/health`
- **Loki**: `/ready` and `/metrics`
- **ClickHouse**: `/ping`

## Storage Considerations

### Persistent Storage
- **Longhorn**: Default storage class for persistence
- **Local Path**: For development/testing
- **S3/GCS/Azure**: Optional for Loki/Tempo

### Storage Requirements
- **Gitea**: 50Gi (repositories + data)
- **Grafana**: 10Gi (dashboards + database)
- **Loki**: 100Gi (logs)
- **ClickHouse**: 100Gi per pod (time-series data)

## Security Configuration

### Secrets Management
All sensitive data is managed via SOPS:
- Database passwords
- Admin credentials
- API tokens
- Encryption keys

### Network Security
- **Ingress**: HTTPS with Let's Encrypt
- **Service Accounts**: Least privilege access
- **Network Policies**: Default deny all, allow specific services

## Scaling Considerations

### Current Setup (Single Backbone)
- All services run on `backbone-01`
- HA achieved through pod replicas
- Node affinity ensures backbone placement

### Future 3:1 Scaling
When adding more nodes:
- **Backbone Nodes**: 3 total (for HA)
- **Frontline Nodes**: 9+ total (for workloads)
- **Service Distribution**: Across backbone nodes
- **Load Balancing**: Kubernetes service load balancing

## Troubleshooting

### Common Issues
1. **Pod Stuck in Pending**: Check node affinity and taints
2. **Health Check Failures**: Verify service endpoints and ports
3. **Storage Issues**: Check PVC status and storage class
4. **Network Issues**: Verify ingress rules and DNS

### Diagnostic Commands
```bash
# Check service status
kubectl get pods -n argocd
kubectl get pods -n gitea

# Check node affinity
kubectl get pods -n argocd -o wide

# Check health checks
kubectl describe pod -n argocd argocd-server-xxx

# Check storage
kubectl get pvc -n gitea
```

## Backup and Recovery

### Automated Backups
- **Gitea**: Database dumps via cronjob
- **Grafana**: Dashboard exports
- **ClickHouse**: Native backup tools
- **Loki**: Table-based backups

### Disaster Recovery
- **ArgoCD**: Git repository as source of truth
- **Configuration**: All in NixOS for reproducibility
- **Data**: Persistent volumes with snapshots

This configuration ensures all backbone services are highly available, properly distributed, and resilient to node failures while maintaining the 3:1 frontline:backbone ratio for future scaling.