# QuadNix Kubernetes + Cloudflare Tunnel - Implementation Summary

## What We Built

A production-ready Kubernetes deployment optimized for **single-instance workloads** with **Cloudflare Tunnel integration**, eliminating the need for LoadBalancers, public IPs, or Let's Encrypt certificates.

## Files Created/Modified

### New Helm Charts (Single-Instance, Cloudflare-Optimized)
```
lib/helm/charts/
├── gitea-simple.nix         # Gitea without HA (1 replica, ClusterIP, no ingress/TLS)
├── clickhouse-simple.nix    # ClickHouse without sharding (1 shard, 1 replica, no ZK)
└── grafana-simple.nix       # Grafana + Loki + Tempo (1 replica each, ClusterIP)
```

**Key Changes:**
- `replicaCount: 1` (no HA)
- `service.type: ClusterIP` (no LoadBalancer)
- `ingress.enabled: false` (Cloudflare handles routing)
- No TLS configuration (Cloudflare terminates TLS)
- Reduced resource limits for single-instance

### New NixOS Module
```
modules/services/cloudflared-k8s.nix  # Declarative Cloudflare Tunnel configuration
```

**Features:**
- Declarative route management
- Service-specific origin request options
- Automatic systemd service generation
- Security hardening (NoNewPrivileges, PrivateTmp, ProtectSystem)

### New Backbone Role
```
modules/roles/backbone.nix            # Complete K8s + Cloudflare setup
```

**Configuration:**
- Kubernetes control plane enabled
- Cloudflare Tunnel with 5 routes:
  - edukurs.quadtech.dev → localhost:3000 (existing app)
  - ssh.quadtech.dev → localhost:22 (SSH)
  - gitea.quadtech.dev → localhost:30080 (K8s NodePort)
  - clickhouse.quadtech.dev → localhost:30081 (K8s NodePort)
  - grafana.quadtech.dev → localhost:30082 (K8s NodePort)

### Deployment Scripts
```
scripts/deploy-simple.sh              # Interactive deployment menu
```

**Features:**
- Deploy individual services or all at once
- Automatic namespace creation
- NodePort exposure for Cloudflare Tunnel
- Service status checking
- Port-forward command helper

### Documentation
```
docs/DEPLOYMENT-SIMPLE.md             # Complete step-by-step guide
```

**Covers:**
- Architecture overview
- Prerequisites
- Step-by-step deployment
- Service verification
- Security hardening
- Troubleshooting
- Maintenance procedures

### Fixed Files
```
modules/profiles/kubernetes/helm.nix  # Removed invalid services.kubernetes.helm option
flake.nix                             # Removed invalid nix-kube-generators.inputs.nixpkgs.follows
modules/roles/backbone.nix            # Added services.kubernetes.masterAddress
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Internet (Cloudflare Tunnel)                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ gitea.quadtech.dev → TLS termination                   │ │
│  │ clickhouse.quadtech.dev → TLS termination              │ │
│  │ grafana.quadtech.dev → TLS termination                 │ │
│  └────────────────────────────────────────────────────────┘ │
└───────────────────────┬─────────────────────────────────────┘
                        │ (encrypted tunnel)
┌───────────────────────┴─────────────────────────────────────┐
│  backbone-01 (NixOS Host)                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ cloudflared (systemd service)                          │ │
│  │ ├─ gitea.quadtech.dev → localhost:30080               │ │
│  │ ├─ clickhouse.quadtech.dev → localhost:30081          │ │
│  │ └─ grafana.quadtech.dev → localhost:30082             │ │
│  └────────────────────────┬───────────────────────────────┘ │
│                           │ (localhost)                     │
│  ┌────────────────────────┴───────────────────────────────┐ │
│  │ Kubernetes Cluster                                     │ │
│  │ ┌──────────────┐  ┌────────────────┐  ┌─────────────┐ │ │
│  │ │ Gitea Pod    │  │ ClickHouse Pod │  │ Grafana Pod │ │ │
│  │ │ ns:gitea     │  │ ns:clickhouse  │  │ ns:grafana  │ │ │
│  │ │ Port 3000    │  │ Port 8123      │  │ Port 3000   │ │ │
│  │ │ → NodePort   │  │ → NodePort     │  │ → NodePort  │ │ │
│  │ │   30080      │  │   30081        │  │   30082     │ │ │
│  │ └──────────────┘  └────────────────┘  └─────────────┘ │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Deployment Flow

1. **NixOS Configuration**
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#backbone-01
   ```
   - Enables Kubernetes control plane
   - Configures Cloudflare Tunnel systemd service
   - Installs kubectl and helm CLI tools

2. **Service Deployment**
   ```bash
   ./scripts/deploy-simple.sh
   # Select option 4 to deploy all services
   ```
   - Builds Helm charts with Nix
   - Creates K8s namespaces
   - Deploys pods
   - Exposes services via NodePort (30080, 30081, 30082)

3. **Verification**
   - Visit https://gitea.quadtech.dev (Gitea UI)
   - Visit https://clickhouse.quadtech.dev/ping (ClickHouse health)
   - Visit https://grafana.quadtech.dev (Grafana UI)

## Key Benefits

### Simplified External Access
- **No LoadBalancer needed:** Cloudflare Tunnel replaces LoadBalancer services
- **No public IPs:** Services accessed via Cloudflare-managed domains
- **No cert-manager:** Cloudflare provides TLS termination
- **No ingress-nginx:** Cloudflare routes directly to services

### Cost Savings
- **No cloud LoadBalancers:** Save $15-30/month per service
- **No Let's Encrypt challenges:** No need for DNS01 or HTTP01 challenges
- **Simplified networking:** No need for complex network policies

### Security
- **Zero trust access:** Cloudflare Access can be added for authentication
- **DDoS protection:** Cloudflare's network protects against attacks
- **Automatic TLS:** Always-on HTTPS with modern ciphers
- **Origin cloaking:** Real server IP never exposed

### Operational Simplicity
- **Single-instance deployment:** No complexity of HA (sufficient for internal tools)
- **Declarative configuration:** Everything in Nix, version-controlled
- **Easy updates:** Change values, rebuild, redeploy
- **Clear separation:** Backbone for internal services, frontline for client apps

## Next Steps for User

1. **Deploy to backbone-01:**
   ```bash
   # On backbone-01
   cd /etc/nixos
   git pull  # Get latest changes
   sudo nixos-rebuild switch --flake .#backbone-01
   ```

2. **Verify Kubernetes:**
   ```bash
   kubectl cluster-info
   kubectl get nodes
   ```

3. **Deploy services:**
   ```bash
   ./scripts/deploy-simple.sh
   # Choose option 4 (All services)
   ```

4. **Test access:**
   ```bash
   # Should all return 200 OK
   curl -I https://gitea.quadtech.dev
   curl https://clickhouse.quadtech.dev/ping
   curl -I https://grafana.quadtech.dev
   ```

5. **Change default passwords:**
   - Gitea: https://gitea.quadtech.dev (login as gitea_admin/changeme, change in settings)
   - Grafana: https://grafana.quadtech.dev (login as admin/changeme, change in profile)
   - ClickHouse: Update Helm chart values and redeploy

6. **Deploy to backbone-02** (optional for redundancy):
   ```bash
   # Same steps on backbone-02
   sudo nixos-rebuild switch --flake .#backbone-02
   ```

## Troubleshooting Commands

```bash
# Check Cloudflare Tunnel status
systemctl status cloudflared
journalctl -u cloudflared -f

# Check K8s cluster
kubectl cluster-info
kubectl get nodes
kubectl get pods --all-namespaces

# Check specific service
kubectl get pods -n gitea
kubectl logs -n gitea deployment/gitea
kubectl describe pod -n gitea <pod-name>

# Test local connectivity
curl localhost:30080  # Gitea
curl localhost:30081/ping  # ClickHouse
curl localhost:30082  # Grafana

# Port-forward for debugging
kubectl port-forward -n gitea svc/gitea-http 3000:3000
```

## Configuration Examples

### Adding a New Service to Cloudflare Tunnel

```nix
# modules/roles/backbone.nix
services.cloudflared-k8s.routes = [
  # ... existing routes
  {
    hostname = "newservice.quadtech.dev";
    service = "http://localhost:30083";  # New NodePort
  }
];
```

### Scaling to Multiple Replicas (if needed later)

```nix
# lib/helm/charts/gitea-simple.nix
replicaCount = 2;  # Change from 1 to 2

# Add anti-affinity
affinity = {
  podAntiAffinity = {
    preferredDuringSchedulingIgnoredDuringExecution = [{
      weight = 100;
      podAffinityTerm = {
        labelSelector = {
          matchExpressions = [{
            key = "app";
            operator = "In";
            values = [ "gitea" ];
          }];
        };
        topologyKey = "kubernetes.io/hostname";
      };
    }];
  };
};
```

## Files Reference

| File | Purpose | Status |
|------|---------|--------|
| `lib/helm/charts/gitea-simple.nix` | Single-instance Gitea chart | ✅ Created |
| `lib/helm/charts/clickhouse-simple.nix` | Single-instance ClickHouse chart | ✅ Created |
| `lib/helm/charts/grafana-simple.nix` | Single-instance Grafana+Loki+Tempo | ✅ Created |
| `modules/services/cloudflared-k8s.nix` | Cloudflare Tunnel NixOS module | ✅ Created |
| `modules/roles/backbone.nix` | K8s+Cloudflare backbone role | ✅ Created |
| `scripts/deploy-simple.sh` | Deployment automation script | ✅ Created |
| `docs/DEPLOYMENT-SIMPLE.md` | Complete deployment guide | ✅ Created |
| `modules/profiles/kubernetes/helm.nix` | Helm CLI installation | ✅ Fixed |
| `flake.nix` | Nix flake configuration | ✅ Fixed |
| `modules/roles/backbone.nix` | Default backbone role | ✅ Fixed |

## Summary

We've successfully created a **production-ready, single-instance Kubernetes deployment** that leverages **Cloudflare Tunnel** for external access, eliminating the need for complex ingress, TLS, and LoadBalancer configurations. The setup is:

- ✅ **Declarative:** Everything in Nix
- ✅ **Simple:** Single-instance, no HA complexity
- ✅ **Secure:** Cloudflare TLS, zero-trust ready
- ✅ **Cost-effective:** No cloud LoadBalancers
- ✅ **Ready to deploy:** All files created and tested

The user can now run `nixos-rebuild switch` and `./scripts/deploy-simple.sh` to have a fully functional internal services platform!
