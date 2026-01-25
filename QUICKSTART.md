# Quick Start: Deploy Services to Kubernetes

## TL;DR

```bash
# 1. Deploy NixOS configuration with K8s + Cloudflare Tunnel
sudo nixos-rebuild switch --flake /etc/nixos#backbone-01

# 2. Verify Kubernetes is running
kubectl cluster-info
kubectl get nodes

# 3. Deploy all services
cd /etc/nixos
./scripts/deploy-simple.sh
# Choose option 4 (Deploy all services)

# 4. Access your services
open https://gitea.quadtech.dev
open https://clickhouse.quadtech.dev
open https://grafana.quadtech.dev
```

## What Was Fixed

The following errors were resolved:

1. ✅ **Removed invalid `services.kubernetes.helm` option**
   - File: `profiles/kubernetes/helm.nix`
   - Now only installs kubectl and helm CLI tools

2. ✅ **Removed invalid `nix-kube-generators.inputs.nixpkgs.follows`**
   - File: `flake.nix`
   - nix-kube-generators doesn't have a nixpkgs input to override

3. ✅ **Added `services.kubernetes.masterAddress`**
   - File: `roles/backbone.nix`
   - Required by NixOS Kubernetes module

## Files Ready for Deployment

### Single-Instance Helm Charts
- `lib/helm/charts/gitea-simple.nix` - Git service (1 replica, ClusterIP)
- `lib/helm/charts/clickhouse-simple.nix` - Analytics DB (1 shard, no ZK)
- `lib/helm/charts/grafana-simple.nix` - Observability (Grafana + Loki + Tempo)

### Cloudflare Tunnel Integration
- `modules/services/cloudflared-k8s.nix` - NixOS module for Cloudflare Tunnel
- `roles/backbone-k8s-cloudflare.nix` - Complete K8s + Cloudflare configuration

### Deployment Automation
- `scripts/deploy-simple.sh` - Interactive deployment menu

## Before You Deploy

### Check Your Current Cloudflare Tunnel

Your current tunnel configuration:
```yaml
tunnel: 9832df66-f04a-40ea-b004-f6f9b100eb14
credentials-file: /home/klajd/.cloudflared/9832df66-f04a-40ea-b004-f6f9b100eb14.json

ingress:
  - hostname: edukurs.quadtech.dev
    service: http://localhost:3000
  - hostname: ssh.quadtech.dev
    service: ssh://localhost:22
  - hostname: gitea.quadtech.dev
    service: http://localhost:8080  # ← Will change to :30080 (K8s NodePort)
  - service: http_status:404
```

After deployment, it will route to:
- `gitea.quadtech.dev` → `localhost:30080` (K8s service via NodePort)
- `clickhouse.quadtech.dev` → `localhost:30081` (new)
- `grafana.quadtech.dev` → `localhost:30082` (new)

## Deployment Options

### Option 1: Use New Backbone Role (Recommended)

Update your host configuration:

```nix
# hosts/backbone-01/configuration.nix
{
  imports = [
    ../../roles/backbone-k8s-cloudflare.nix  # ← Use this instead of backbone.nix
  ];
}
```

Then deploy:
```bash
sudo nixos-rebuild switch --flake /etc/nixos#backbone-01
```

### Option 2: Keep Existing backbone.nix (Already Fixed)

The existing `roles/backbone.nix` is now fixed and will work. It enables:
- ✅ Kubernetes control plane
- ✅ kubectl and helm CLI tools
- ✅ Firewall rules (22, 443, 6443)

But you'll need to configure Cloudflare Tunnel manually or use the module.

## Step-by-Step Deployment

### 1. Pull Latest Changes

```bash
cd /etc/nixos
git status  # Check if there are local changes
git pull    # Get latest configurations
```

### 2. Review What Will Change

```bash
# Build without switching
sudo nixos-rebuild build --flake /etc/nixos#backbone-01

# See what packages will be added/removed
nix store diff-closures
```

### 3. Deploy NixOS Configuration

```bash
sudo nixos-rebuild switch --flake /etc/nixos#backbone-01
```

**Expected changes:**
- Kubernetes control plane enabled
- Cloudflare Tunnel reconfigured (if using new role)
- kubectl and helm installed

### 4. Verify Kubernetes

```bash
# Check cluster is running
kubectl cluster-info

# Should show:
# Kubernetes control plane is running at https://127.0.0.1:6443

# Check nodes
kubectl get nodes

# Should show:
# NAME           STATUS   ROLES    AGE   VERSION
# backbone-01    Ready    master   Xs    vX.XX.X
```

### 5. Deploy Services

```bash
cd /etc/nixos
./scripts/deploy-simple.sh
```

**Menu:**
```
================================================
  QuadNix Single-Instance K8s Deployment
================================================

Available services:
  1) Gitea (Git service)
  2) ClickHouse (Analytics database)
  3) Grafana (Observability)
  4) All services              ← Choose this
  5) Show service status
  6) Port-forward services (for Cloudflare Tunnel)
  0) Exit

Select option: 4
```

### 6. Monitor Deployment

```bash
# Watch pods being created
watch kubectl get pods --all-namespaces

# Expected output:
# NAMESPACE     NAME                      READY   STATUS    RESTARTS   AGE
# gitea         gitea-xxx                 1/1     Running   0          2m
# clickhouse    clickhouse-0              1/1     Running   0          2m
# grafana       grafana-xxx               1/1     Running   0          2m
```

### 7. Verify Services Are Accessible

```bash
# Test local connectivity
curl localhost:30080  # Should return Gitea HTML
curl localhost:30081/ping  # Should return "Ok."
curl localhost:30082  # Should return Grafana HTML

# Test Cloudflare Tunnel routing
curl https://gitea.quadtech.dev
curl https://clickhouse.quadtech.dev/ping
curl https://grafana.quadtech.dev
```

### 8. Access Services

Open in browser:
- **Gitea:** https://gitea.quadtech.dev
  - Username: `gitea_admin`
  - Password: `changeme` (change immediately!)

- **Grafana:** https://grafana.quadtech.dev
  - Username: `admin`
  - Password: `changeme` (change immediately!)

- **ClickHouse:** https://clickhouse.quadtech.dev
  - User: `admin`
  - Password: `changeme` (change in Helm values)

## Troubleshooting

### Error: `nixos-rebuild` fails

```bash
# Check syntax errors
sudo nixos-rebuild build --flake /etc/nixos#backbone-01 --show-trace

# Common issues:
# - Missing imports
# - Typos in configuration
# - Missing required options
```

### Error: `kubectl cluster-info` fails

```bash
# Check if Kubernetes services are running
systemctl status kube-apiserver
systemctl status kube-controller-manager
systemctl status kube-scheduler
systemctl status etcd

# Check logs
journalctl -u kube-apiserver -f
```

### Error: Pods stuck in `Pending`

```bash
# Check pod details
kubectl describe pod -n gitea <pod-name>

# Common issues:
# - No PersistentVolume provisioner (install local-path-provisioner)
# - Insufficient resources
# - Image pull errors
```

### Error: Services not accessible via Cloudflare

```bash
# Check Cloudflare Tunnel
systemctl status cloudflared
journalctl -u cloudflared -f

# Verify NodePort services exist
kubectl get svc -n gitea
kubectl get svc -n clickhouse
kubectl get svc -n grafana

# Should show TYPE: NodePort
```

## Rollback

If something goes wrong:

```bash
# Rollback NixOS
sudo nixos-rebuild switch --rollback

# Delete K8s services
kubectl delete namespace gitea
kubectl delete namespace clickhouse
kubectl delete namespace grafana
```

## Default Credentials (Change Immediately!)

| Service    | Username      | Password  | Change Method |
|------------|---------------|-----------|---------------|
| Gitea      | `gitea_admin` | `changeme`| Via web UI    |
| Grafana    | `admin`       | `changeme`| Via web UI    |
| ClickHouse | `admin`       | `changeme`| Update Helm chart |

## What's Next?

After successful deployment:

1. **Change all default passwords**
2. **Set up backups** for persistent data
3. **Configure monitoring** (Prometheus is ready to deploy)
4. **Deploy client apps** to frontline nodes
5. **Set up secrets management** (SOPS or sealed-secrets)

## Quick Reference

```bash
# Rebuild NixOS
sudo nixos-rebuild switch --flake /etc/nixos#backbone-01

# Deploy services
./scripts/deploy-simple.sh

# Check service status
kubectl get pods -n gitea
kubectl get pods -n clickhouse
kubectl get pods -n grafana

# View logs
kubectl logs -n gitea deployment/gitea
kubectl logs -n clickhouse statefulset/clickhouse
kubectl logs -n grafana deployment/grafana

# Restart service
kubectl rollout restart -n gitea deployment/gitea

# Update service
# 1. Edit Helm chart: vim lib/helm/charts/gitea-simple.nix
# 2. Rebuild: nix build .#helmCharts.x86_64-linux.gitea-simple
# 3. Apply: kubectl apply -f result/
```

## Documentation

- **Complete deployment guide:** `docs/DEPLOYMENT-SIMPLE.md`
- **Implementation summary:** `docs/IMPLEMENTATION-SUMMARY.md`
- **Helm charts documentation:** `lib/helm/README.md`
- **Cloudflare integration:** `docs/CLOUDFLARE-TUNNEL.md`

## Support

If you encounter issues:
1. Check the logs: `journalctl -u <service> -f`
2. Review pod status: `kubectl describe pod -n <namespace> <pod-name>`
3. Check Cloudflare Tunnel: `systemctl status cloudflared`

All services are configured for single-instance deployment. No HA complexity means easier debugging!
