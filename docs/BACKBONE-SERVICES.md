# Running Services on Backbone-01

## TL;DR - Current Status

**NO**, the current config will **NOT** run Gitea/ClickHouse/Grafana on backbone-01 because:

1. `roles/backbone.nix` has Kubernetes control plane **commented out** (line 7)
2. Only `services/gitea.nix` is imported, but it runs as a **NixOS systemd service** (not Kubernetes)
3. ClickHouse and other services are **commented out** (line 9-10)

## Two Approaches to Run Services

You have two options for running services on backbone-01:

### Option 1: NixOS Services (Simpler, Single-Node)

Run services directly on the NixOS host as systemd services.

**Pros:**
- ✅ Simpler setup, no Kubernetes needed
- ✅ Lower resource overhead
- ✅ Good for single-server deployments
- ✅ Easier to debug (systemd logs)

**Cons:**
- ❌ No high availability
- ❌ No automatic scaling
- ❌ No isolation from client apps
- ❌ Harder to update/rollback

**Configuration:**

```nix
# roles/backbone.nix
{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../services/gitea.nix       # Gitea on port 443
    ../services/clickhouse.nix  # ClickHouse on ports 8123, 9000
  ];
  
  # No Kubernetes needed
}
```

**Deploy:**
```sh
sudo nixos-rebuild switch --flake .#backbone-01
```

**Access:**
- Gitea: https://git.quadtech.dev (or http://192.168.1.10)
- ClickHouse: http://192.168.1.10:8123

---

### Option 2: Kubernetes Services (Production-Ready, HA)

Run services on Kubernetes using Helm charts.

**Pros:**
- ✅ High availability (multiple replicas)
- ✅ Automatic scaling and self-healing
- ✅ Better isolation (namespaces)
- ✅ Easy rollbacks with Helm
- ✅ Separation from client apps (frontline nodes)
- ✅ Production-grade monitoring

**Cons:**
- ❌ More complex setup
- ❌ Higher resource requirements
- ❌ Steeper learning curve

**Configuration:**

```nix
# roles/backbone.nix
{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/helm.nix
  ];
  
  services.kubernetes = {
    roles = [ "master" ];
    controlPlane.enable = true;
  };
}
```

**Deploy:**
```sh
# 1. Deploy NixOS with K8s
sudo nixos-rebuild switch --flake .#backbone-01

# 2. Deploy services with Helm
nix build .#helmCharts.x86_64-linux.all.gitea
helm install gitea ./result/*.tgz -n gitea --create-namespace
```

## Recommended Approach

Based on your infrastructure goals:

### If You Want...

**Quick testing / Single server:**
→ **Use Option 1** (NixOS services)

**Production deployment / HA / Client separation:**
→ **Use Option 2** (Kubernetes)

## How to Enable Services Right Now

Here's what to change to get services running:

### Quick Fix - Option 1 (NixOS Services)

**1. Update `roles/backbone.nix`:**

```nix
{ config, pkgs, ... }:

{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../services/gitea.nix
    ../services/clickhouse.nix
  ];

  networking.firewall.allowedTCPPorts = [
    22 80 443     # SSH, HTTP, HTTPS
    2222          # Gitea SSH
    8123 9000     # ClickHouse HTTP, TCP
    6443          # If you add K8s later
  ];
}
```

**2. Deploy:**

```sh
sudo nixos-rebuild switch --flake .#backbone-01
```

**3. Verify:**

```sh
# Check services
systemctl status gitea
systemctl status clickhouse

# Access Gitea
curl http://localhost:3000  # Or whatever port is configured

# Access ClickHouse
curl http://localhost:8123
```

### Proper Fix - Option 2 (Kubernetes)

**1. Replace `roles/backbone.nix` with the updated version:**

```sh
# Backup current
cp roles/backbone.nix roles/backbone.nix.backup

# Use the updated version
cp roles/backbone-updated.nix roles/backbone.nix
```

Or manually edit to uncomment the Kubernetes imports (see `roles/backbone-updated.nix`).

**2. Deploy NixOS:**

```sh
sudo nixos-rebuild switch --flake .#backbone-01
```

**3. Wait for Kubernetes to start:**

```sh
# May take 2-3 minutes
kubectl get nodes
```

**4. Deploy services:**

```sh
# Use the deployment script
./scripts/deploy.sh

# Or manually
kubectl apply -f manifests/backbone/namespaces.yaml
nix build .#helmCharts.x86_64-linux.all.gitea
helm install gitea ./result/*.tgz -n gitea --create-namespace
```

## What Each File Does

### Current Files

```
roles/backbone.nix
├── Lines 7: # ../profiles/kubernetes/control-plane.nix  ← COMMENTED OUT
├── Line 8:  ../services/gitea.nix                       ← ENABLED (NixOS service)
└── Line 9:  # ../services/clickhouse.nix                ← COMMENTED OUT

services/gitea.nix
└── Configures Gitea as a systemd service on the host

services/clickhouse.nix
└── Configures ClickHouse as a systemd service on the host
```

### What Needs to Happen

**For NixOS Services (Option 1):**
```diff
  roles/backbone.nix
- # ../services/clickhouse.nix
+ ../services/clickhouse.nix
```

**For Kubernetes Services (Option 2):**
```diff
  roles/backbone.nix
- # ../profiles/kubernetes/control-plane.nix
+ ../profiles/kubernetes/control-plane.nix
+ ../profiles/kubernetes/helm.nix

- ../services/gitea.nix
- # ../services/clickhouse.nix
```

Then deploy Helm charts separately.

## Testing Your Choice

### Test Option 1 (NixOS)

```sh
# After deploying
systemctl status gitea
systemctl status clickhouse
curl http://localhost:8123  # ClickHouse
```

### Test Option 2 (Kubernetes)

```sh
# After deploying NixOS
kubectl get nodes

# After deploying Helm charts
kubectl get pods -n gitea
kubectl get pods -n clickhouse
kubectl get svc --all-namespaces
```

## Migration Path

Start with **Option 1** (simpler) and migrate to **Option 2** later:

```
1. Deploy with NixOS services (Option 1)
   └── Test and validate everything works

2. Set up Kubernetes (enable control-plane)
   └── Verify cluster is healthy

3. Migrate data to Kubernetes
   └── Export from NixOS services, import to K8s

4. Switch over (disable NixOS services)
   └── Comment out services/*, use Helm charts
```

## My Recommendation

Given your setup (backbone for internal, frontline for clients):

**Use Option 2 (Kubernetes)** because:
1. You already have 2 backbone + 2 frontline nodes → perfect for K8s
2. Client isolation is important → K8s namespaces + node selectors
3. HA for internal services → K8s replication
4. Helm charts are already configured → just deploy them

## Next Steps

**Choose Your Path:**

**Path A - Quick Start (NixOS Services):**
1. Uncomment services in `roles/backbone.nix`
2. Deploy: `sudo nixos-rebuild switch --flake .#backbone-01`
3. Access services directly on backbone-01

**Path B - Production (Kubernetes):**
1. Use `roles/backbone-updated.nix` as your `roles/backbone.nix`
2. Deploy: `sudo nixos-rebuild switch --flake .#backbone-01`
3. Run: `./scripts/deploy.sh` to deploy Helm charts
4. Access services via ingress

## Summary

| Aspect | Option 1: NixOS | Option 2: Kubernetes |
|--------|----------------|---------------------|
| Setup Complexity | Low | High |
| Resource Usage | Low | Medium-High |
| High Availability | No | Yes |
| Scalability | Manual | Automatic |
| Client Isolation | No | Yes (node selectors) |
| Monitoring | Basic | Advanced (Prometheus) |
| Rollbacks | nixos-rebuild switch | helm rollback |
| Best For | Single server, testing | Multi-node, production |

**Current config will work for Option 1** if you uncomment the services.
**For Option 2**, you need to enable Kubernetes control plane and deploy Helm charts.

Your choice! 🚀
