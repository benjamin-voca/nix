# QuadNix Quick Reference

## Infrastructure Overview

```
Backbone (Internal Services)
├── backbone-01 (192.168.1.10) - Primary control plane
├── backbone-02 (192.168.1.11) - Secondary control plane
└── Services:
    ├── Gitea       git.quadtech.dev
    ├── ClickHouse  clickhouse.quadtech.dev
    ├── Grafana     grafana.quadtech.dev
    └── Prometheus  prometheus.quadtech.dev

Frontline (Client Applications)
├── frontline-01 (192.168.1.20) - Worker node
├── frontline-02 (192.168.1.21) - Worker node
└── Your client apps run here
```

## Quick Start

### 1. Deploy Infrastructure (Automated)

```sh
./scripts/deploy.sh
```

Select "Deploy All (Recommended)" and follow prompts.

### 2. Deploy Infrastructure (Manual)

```sh
# Step 1: Deploy NixOS on backbone nodes
sudo nixos-rebuild switch --flake .#backbone-01
sudo nixos-rebuild switch --flake .#backbone-02

# Step 2: Deploy NixOS on frontline nodes
sudo nixos-rebuild switch --flake .#frontline-01
sudo nixos-rebuild switch --flake .#frontline-02

# Step 3: Deploy Kubernetes services
kubectl apply -f manifests/backbone/namespaces.yaml

# Infrastructure
helm install ingress-nginx <chart> -n ingress-nginx
helm install cert-manager <chart> -n cert-manager

# Monitoring
helm install prometheus <chart> -n monitoring
helm install grafana <chart> -n grafana
helm install loki <chart> -n loki

# Services
helm install gitea <chart> -n gitea
helm install clickhouse-operator <chart> -n clickhouse-operator
helm install clickhouse <chart> -n clickhouse
```

## Common Commands

### NixOS Operations

```sh
# Build configuration
nix build .#nixosConfigurations.backbone-01.config.system.build.toplevel

# Deploy to local system
sudo nixos-rebuild switch --flake .#backbone-01

# Deploy remotely
nixos-rebuild switch --flake .#backbone-01 --target-host root@192.168.1.10

# Update flake
nix flake update
```

### Kubernetes Operations

```sh
# View nodes
kubectl get nodes -o wide

# View all pods
kubectl get pods --all-namespaces

# View services
kubectl get svc --all-namespaces

# View ingresses
kubectl get ingress --all-namespaces

# Describe resource
kubectl describe pod <pod-name> -n <namespace>

# View logs
kubectl logs <pod-name> -n <namespace>

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
```

### Helm Operations

```sh
# List releases
helm list --all-namespaces

# Get values
helm get values <release> -n <namespace>

# Upgrade release
helm upgrade <release> <chart> -n <namespace>

# Rollback release
helm rollback <release> <revision> -n <namespace>

# Uninstall release
helm uninstall <release> -n <namespace>
```

### Build Helm Charts

```sh
# Build single chart
nix build .#helmCharts.x86_64-linux.all.gitea

# Build all charts
nix build .#helmCharts.x86_64-linux.all

# List available charts
nix eval .#helmCharts.x86_64-linux --apply 'charts: builtins.attrNames charts.all'
```

## Service Access

### Default Credentials (⚠️ CHANGE THESE!)

```
Gitea:      admin / changeme
Grafana:    admin / changeme
ClickHouse: admin / changeme
```

### Service URLs

```
Gitea:      https://git.quadtech.dev
Grafana:    https://grafana.quadtech.dev
ClickHouse: https://clickhouse.quadtech.dev
Prometheus: https://prometheus.quadtech.dev (via Grafana)
```

### SSH Access

```sh
# Gitea SSH
git clone git@git.quadtech.dev:2222/user/repo.git

# Backbone nodes
ssh root@mainssh.quadtech.dev  # backbone-01
ssh root@192.168.1.11           # backbone-02

# Frontline nodes
ssh root@192.168.1.20           # frontline-01
ssh root@192.168.1.21           # frontline-02
```

## Deploy Client Application

### Quick Deploy

```sh
# Apply example app
kubectl apply -f manifests/frontline/examples/web-app.yaml

# Check status
kubectl get pods -n client-apps
kubectl get ingress -n client-apps
```

### Custom Application

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-namespace
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      nodeSelector:
        kubernetes.io/role: node  # Runs on frontline
      containers:
      - name: my-app
        image: my-app:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

## Troubleshooting

### Check Cluster Health

```sh
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get componentstatuses  # Deprecated but useful
```

### Pod Not Starting

```sh
# Describe pod
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### Service Not Accessible

```sh
# Check service
kubectl get svc <service-name> -n <namespace>

# Check endpoints
kubectl get endpoints <service-name> -n <namespace>

# Check ingress
kubectl describe ingress <ingress-name> -n <namespace>
```

### Network Issues

```sh
# Test DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Test connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- /bin/bash
```

### Storage Issues

```sh
# Check PVCs
kubectl get pvc --all-namespaces

# Check PVs
kubectl get pv

# Describe PVC
kubectl describe pvc <pvc-name> -n <namespace>
```

## Maintenance

### Update System

```sh
# Update flake inputs
nix flake update

# Rebuild and deploy
sudo nixos-rebuild switch --flake .#backbone-01
```

### Update Service

```sh
# Update Helm chart
nix flake update nixhelm
nix build .#helmCharts.x86_64-linux.all.gitea

# Upgrade release
helm upgrade gitea ./result/*.tgz -n gitea
```

### Backup

```sh
# Backup important PVCs
kubectl get pvc -n gitea  # Find PVC name
kubectl exec -n gitea <pod-name> -- tar czf - /data > gitea-backup.tar.gz
```

### Scale Application

```sh
# Scale deployment
kubectl scale deployment <name> -n <namespace> --replicas=5

# Autoscale
kubectl autoscale deployment <name> -n <namespace> --min=2 --max=10 --cpu-percent=70
```

## Monitoring

### View Metrics in Grafana

1. Access https://grafana.quadtech.dev
2. Login with admin credentials
3. Navigate to Dashboards
4. Pre-configured dashboards available for Kubernetes, nodes, services

### View Logs in Loki

1. Grafana → Explore
2. Select "Loki" datasource
3. Query examples:
   ```
   {namespace="gitea"}
   {app="my-app"}
   {namespace="client-apps"} |= "error"
   ```

### Query Prometheus

1. Grafana → Explore
2. Select "Prometheus" datasource
3. Query examples:
   ```
   rate(http_requests_total[5m])
   container_memory_usage_bytes{namespace="gitea"}
   ```

## Documentation

- **Deployment Guide**: `docs/DEPLOYMENT.md`
- **Helm Charts**: `lib/helm/README.md`
- **Cachix Setup**: `docs/CACHIX.md`
- **Helm Chart Catalog**: `lib/helm/CHARTS.md`

## Emergency Contacts

⚠️ For production systems, add your team's contact information here.

## Version Info

Check versions:

```sh
# NixOS
nixos-version

# Kubernetes
kubectl version

# Helm
helm version
```
