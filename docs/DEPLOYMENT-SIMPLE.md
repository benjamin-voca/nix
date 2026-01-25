# Deployment Guide: Single-Instance Kubernetes with Cloudflare Tunnel

This guide walks you through deploying internal services (Gitea, ClickHouse, Grafana) on Kubernetes with Cloudflare Tunnel for external access.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Cloudflare Tunnel (cloudflared)                            │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ gitea.quadtech.dev → localhost:30080                   │ │
│  │ clickhouse.quadtech.dev → localhost:30081              │ │
│  │ grafana.quadtech.dev → localhost:30082                 │ │
│  └────────────────────────────────────────────────────────┘ │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────┴─────────────────────────────────────┐
│  Kubernetes Cluster (backbone-01)                           │
│  ┌────────────┐  ┌──────────────┐  ┌────────────┐          │
│  │   Gitea    │  │  ClickHouse  │  │  Grafana   │          │
│  │  (ns:gitea)│  │(ns:clickhouse)│ │ (ns:grafana)│         │
│  │  Port 3000 │  │  Port 8123   │  │  Port 3000 │          │
│  └────────────┘  └──────────────┘  └────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

**Key Design Decisions:**
- **Single-instance deployments** (no HA) - simpler, sufficient for internal services
- **ClusterIP services** - no LoadBalancer needed, Cloudflare handles external access
- **No TLS in K8s** - Cloudflare Tunnel provides TLS termination
- **NodePort exposure** - Local ports for Cloudflare Tunnel to connect

## Prerequisites

1. **Backbone node with Kubernetes enabled**
2. **Cloudflare Tunnel configured** (already running)
3. **kubectl access** to the cluster
4. **Nix with flakes** enabled

## Step 1: Update Backbone Configuration

Choose one of these options:

### Option A: Use New Backbone Role (Recommended)

Update your host configuration to use the new role:

```nix
# hosts/backbone-01/configuration.nix
{
  imports = [
    ../../roles/backbone-k8s-cloudflare.nix
  ];
}
```

### Option B: Manual Configuration

If you want to keep your existing `roles/backbone.nix`, add the Cloudflare module:

```nix
# roles/backbone.nix
{
  imports = [
    # ... existing imports
    ../modules/services/cloudflared-k8s.nix
  ];

  services.cloudflared-k8s = {
    enable = true;
    tunnelId = "9832df66-f04a-40ea-b004-f6f9b100eb14";
    credentialsFile = "/home/klajd/.cloudflared/9832df66-f04a-40ea-b004-f6f9b100eb14.json";

    routes = [
      { hostname = "edukurs.quadtech.dev"; service = "http://localhost:3000"; }
      { hostname = "ssh.quadtech.dev"; service = "ssh://localhost:22"; }
      { hostname = "gitea.quadtech.dev"; service = "http://localhost:30080"; }
      { hostname = "clickhouse.quadtech.dev"; service = "http://localhost:30081"; }
      { hostname = "grafana.quadtech.dev"; service = "http://localhost:30082"; }
    ];
  };
}
```

## Step 2: Deploy NixOS Configuration

```bash
# Build the configuration
sudo nixos-rebuild build

# Review changes
nix store diff-closures

# Apply the configuration
sudo nixos-rebuild switch

# Verify Cloudflare Tunnel is running
systemctl status cloudflared
```

## Step 3: Verify Kubernetes Cluster

```bash
# Check cluster status
kubectl cluster-info

# Verify nodes are ready
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system
```

## Step 4: Deploy Services

Use the simplified deployment script:

```bash
cd /path/to/QuadNix
./scripts/deploy-simple.sh
```

**Menu Options:**
1. Deploy Gitea only
2. Deploy ClickHouse only
3. Deploy Grafana only
4. **Deploy all services** (recommended for first deployment)
5. Show service status
6. Show port-forward commands

### Manual Deployment (Alternative)

If you prefer to deploy manually:

```bash
# Build Helm charts
nix build .#helmCharts.x86_64-linux.gitea-simple
nix build .#helmCharts.x86_64-linux.clickhouse-simple
nix build .#helmCharts.x86_64-linux.grafana-simple

# Create namespaces
kubectl create namespace gitea
kubectl create namespace clickhouse
kubectl create namespace grafana

# Deploy charts
kubectl apply -f result/  # For each chart

# Expose via NodePort
kubectl -n gitea patch svc gitea-http -p '{"spec":{"type":"NodePort","ports":[{"port":3000,"nodePort":30080}]}}'
kubectl -n clickhouse patch svc clickhouse -p '{"spec":{"type":"NodePort","ports":[{"port":8123,"nodePort":30081}]}}'
kubectl -n grafana patch svc grafana -p '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30082}]}}'
```

## Step 5: Verify Services

```bash
# Check pod status
kubectl get pods -n gitea
kubectl get pods -n clickhouse
kubectl get pods -n grafana

# Check services
kubectl get svc -n gitea
kubectl get svc -n clickhouse
kubectl get svc -n grafana

# Check logs if there are issues
kubectl logs -n gitea deployment/gitea
kubectl logs -n clickhouse statefulset/clickhouse
kubectl logs -n grafana deployment/grafana
```

## Step 6: Access Services

Your services should now be accessible via Cloudflare Tunnel:

- **Gitea:** https://gitea.quadtech.dev
- **ClickHouse:** https://clickhouse.quadtech.dev
- **Grafana:** https://grafana.quadtech.dev

### Default Credentials

**Gitea:**
- Username: `gitea_admin`
- Password: `changeme` (change immediately!)

**ClickHouse:**
- User: `admin`
- Password: `changeme` (change immediately!)

**Grafana:**
- Username: `admin`
- Password: `changeme` (change immediately!)

## Step 7: Secure Your Services

### Change Default Passwords

**Gitea:**
```bash
kubectl exec -n gitea deployment/gitea -- gitea admin user change-password --username gitea_admin --password <NEW_PASSWORD>
```

**Grafana:**
Access https://grafana.quadtech.dev and change password via UI.

**ClickHouse:**
Update the Helm chart values and redeploy.

### Use Secrets Management

For production, integrate SOPS or sealed-secrets:

```nix
# Example with SOPS
sops.secrets."gitea/admin-password" = {
  sopsFile = ./secrets.yaml;
  owner = "gitea";
};
```

## Troubleshooting

### Services Not Accessible via Cloudflare

**Check Cloudflare Tunnel:**
```bash
systemctl status cloudflared
journalctl -u cloudflared -f
```

**Verify NodePort exposure:**
```bash
kubectl get svc -n gitea gitea-http
# Should show TYPE: NodePort and PORT(S): 3000:30080/TCP
```

**Test local connectivity:**
```bash
curl localhost:30080  # Should return Gitea
curl localhost:30081/ping  # Should return "Ok." from ClickHouse
curl localhost:30082  # Should return Grafana
```

### Pods Not Starting

**Check pod status:**
```bash
kubectl describe pod -n gitea <pod-name>
kubectl logs -n gitea <pod-name>
```

**Common issues:**
- **ImagePullBackOff:** Check internet connectivity
- **Pending:** Check if PersistentVolumes can be created
- **CrashLoopBackOff:** Check logs for application errors

### Persistent Volume Issues

**Check PV/PVC status:**
```bash
kubectl get pv
kubectl get pvc -n gitea
kubectl get pvc -n clickhouse
kubectl get pvc -n grafana
```

**If using local-path provisioner:**
```bash
kubectl get pods -n kube-system | grep local-path
```

## Next Steps

1. **Set up monitoring:** Deploy Prometheus to monitor your services
2. **Configure backups:** Set up automated backups for persistent data
3. **Deploy client apps:** Use frontline nodes for client applications
4. **Implement RBAC:** Configure Kubernetes RBAC for security
5. **Add network policies:** Restrict inter-pod communication

## Configuration Reference

### Cloudflare Tunnel Configuration

Location: `/etc/cloudflared/config.yml`

```yaml
tunnel: 9832df66-f04a-40ea-b004-f6f9b100eb14
credentials-file: /home/klajd/.cloudflared/9832df66-f04a-40ea-b004-f6f9b100eb14.json

ingress:
  - hostname: gitea.quadtech.dev
    service: http://localhost:30080
  - hostname: clickhouse.quadtech.dev
    service: http://localhost:30081
  - hostname: grafana.quadtech.dev
    service: http://localhost:30082
  - service: http_status:404
```

### Service Ports

| Service    | K8s Port | NodePort | Cloudflare Route            |
|------------|----------|----------|-----------------------------|
| Gitea      | 3000     | 30080    | gitea.quadtech.dev          |
| ClickHouse | 8123     | 30081    | clickhouse.quadtech.dev     |
| Grafana    | 80       | 30082    | grafana.quadtech.dev        |

### Helm Chart Locations

- `lib/helm/charts/gitea-simple.nix`
- `lib/helm/charts/clickhouse-simple.nix`
- `lib/helm/charts/grafana-simple.nix`

## Rollback Procedure

If something goes wrong:

```bash
# Rollback NixOS configuration
sudo nixos-rebuild switch --rollback

# Delete Kubernetes deployments
kubectl delete namespace gitea
kubectl delete namespace clickhouse
kubectl delete namespace grafana

# Restart from Step 2
```

## Maintenance

### Updating Services

```bash
# Update chart configuration
vim lib/helm/charts/gitea-simple.nix

# Rebuild and redeploy
nix build .#helmCharts.x86_64-linux.gitea-simple
kubectl apply -f result/
```

### Viewing Logs

```bash
# Real-time logs
kubectl logs -n gitea -f deployment/gitea

# All pods in namespace
kubectl logs -n clickhouse --all-containers=true --tail=100
```

### Scaling (if needed later)

To scale to multiple replicas:

```bash
kubectl scale -n gitea deployment/gitea --replicas=2
```

## Support

For issues or questions:
- Check `docs/QUICKREF.md` for quick commands
- Review `docs/BACKBONE-SERVICES.md` for architecture details
- See `lib/helm/README.md` for Helm chart documentation
