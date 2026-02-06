# Cloudflare Tunnel Integration

## Impact on QuadNix Infrastructure

**YES**, Cloudflare Tunnel significantly impacts your deployment because:

1. ✅ **No public IP needed** - Services accessed via Cloudflare's network
2. ✅ **Automatic HTTPS** - Cloudflare handles TLS termination
3. ⚠️ **Ingress controller changes** - May not need NGINX ingress
4. ⚠️ **Cert-manager changes** - May not need Let's Encrypt
5. ⚠️ **DNS is handled by Cloudflare** - No need for external DNS

## Current Cloudflare Setup

Based on your configuration:

```nix
# modules/services/cloudflared-k8s.nix (enabled from modules/roles/backbone.nix)
systemd.services.cloudflared-k8s = {
  ExecStart = "cloudflared --config /etc/cloudflared/config.json tunnel run";
};
```

This runs a Cloudflare Tunnel daemon that connects to Cloudflare's network.

## Architecture with Cloudflare Tunnel

### Traditional Setup (Without Cloudflare)
```
Internet → Public IP → Firewall → Ingress Controller → Services
                                   ↓
                              cert-manager (Let's Encrypt)
```

### Your Setup (With Cloudflare Tunnel)
```
Internet → Cloudflare Network → Cloudflare Tunnel → Services (localhost)
           ↓
       TLS/SSL handled by Cloudflare
       DNS handled by Cloudflare
```

## What This Means for Your Deployment

### 1. Ingress Controller (Optional)

You have **two options**:

#### **Option A: No Ingress (Simpler with Cloudflare)**
- Cloudflare Tunnel routes directly to service ports
- No need for ingress-nginx
- Configure in Cloudflare Tunnel config

```yaml
# /etc/cloudflared/config.yml
tunnel: <your-tunnel-id>
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: gitea.quadtech.dev
    service: http://localhost:3000
  - hostname: clickhouse.quadtech.dev
    service: http://localhost:8123
  - hostname: grafana.quadtech.dev
    service: http://localhost:3000
  - service: http_status:404
```

#### **Option B: Keep Ingress (More Flexible)**
- Use ingress-nginx internally
- Cloudflare Tunnel → ingress-nginx → services
- Better for complex routing

```yaml
# /etc/cloudflared/config.yml
ingress:
  - hostname: "*.quadtech.dev"
    service: http://localhost:80  # Points to ingress-nginx
  - service: http_status:404
```

### 2. TLS Certificates (NOT Needed)

**Skip cert-manager and Let's Encrypt** because:
- ✅ Cloudflare handles TLS termination
- ✅ Automatic SSL certificates from Cloudflare
- ✅ No need for cert-manager in your cluster

### 3. Load Balancer (NOT Needed)

**Skip LoadBalancer services** because:
- ✅ No public IP exposure needed
- ✅ All traffic goes through Cloudflare Tunnel
- ✅ Use ClusterIP or NodePort instead

### 4. Firewall Rules

**Minimal firewall rules needed**:
```nix
networking.firewall.allowedTCPPorts = [
  22    # SSH
  # NO need for 80, 443 - Cloudflare Tunnel uses outbound connections
];
```

All inbound traffic comes through the Cloudflare Tunnel (outbound connection from your server).

## Updated Deployment Strategy

### For NixOS Services (Option 1)

```nix
# modules/roles/backbone.nix
{
  imports = [
    ../profiles/server.nix
    ../services/gitea.nix
    ../services/clickhouse.nix
  ];
  
  # Minimal firewall - Cloudflare Tunnel uses outbound
  networking.firewall.allowedTCPPorts = [ 22 ];
  
  # Cloudflare Tunnel configuration
  services.cloudflared-k8s.enable = true;
}
```

**Cloudflare Tunnel Config:**
```yaml
# /etc/cloudflared/config.yml
tunnel: <your-tunnel-id>
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: gitea.quadtech.dev
    service: http://localhost:3000  # Gitea port
  - hostname: clickhouse.quadtech.dev
    service: http://localhost:8123  # ClickHouse HTTP
  - service: http_status:404
```

### For Kubernetes Services (Option 2)

#### Recommended: Cloudflare → Services (No Ingress)

```yaml
# /etc/cloudflared/config.yml
tunnel: <your-tunnel-id>
credentials-file: /etc/cloudflared/credentials.json

ingress:
  # Point directly to Kubernetes services
  - hostname: gitea.quadtech.dev
    service: http://gitea.gitea.svc.cluster.local:3000
  - hostname: clickhouse.quadtech.dev
    service: http://clickhouse.clickhouse.svc.cluster.local:8123
  - hostname: grafana.quadtech.dev
    service: http://grafana.grafana.svc.cluster.local:80
  - service: http_status:404
```

**Kubernetes Services:**
```yaml
# Use ClusterIP (not LoadBalancer)
apiVersion: v1
kind: Service
metadata:
  name: gitea
  namespace: gitea
spec:
  type: ClusterIP  # NOT LoadBalancer
  selector:
    app: gitea
  ports:
  - port: 3000
```

#### Alternative: Cloudflare → Ingress → Services

```yaml
# /etc/cloudflared/config.yml
ingress:
  - hostname: "*.quadtech.dev"
    service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
  - service: http_status:404
```

Then use standard Kubernetes Ingress resources (but without TLS sections).

## Helm Chart Adjustments

### Gitea Chart

```nix
# lib/helm/charts/gitea.nix
{
  gitea = helmLib.buildChart {
    # ... existing config ...
    values = {
      service = {
        http = {
          type = "ClusterIP";  # NOT LoadBalancer
          port = 3000;
        };
      };
      ingress = {
        enabled = false;  # Cloudflare handles routing
        # OR keep enabled but remove TLS:
        enabled = true;
        className = "nginx";
        hosts = [{
          host = "gitea.quadtech.dev";
          paths = [{ path = "/"; pathType = "Prefix"; }];
        }];
        # NO tls section - Cloudflare handles it
      };
    };
  };
}
```

### All Charts Pattern

For all Helm charts, adjust:

```diff
  service = {
-   type = "LoadBalancer";
+   type = "ClusterIP";
  };
  
  ingress = {
    enabled = true;  # Optional - see above
-   tls = [{ ... }];  # Remove TLS config
  };
```

## DNS Configuration

In Cloudflare Dashboard:

1. **Create Tunnel** (if not exists):
   - Cloudflare Zero Trust → Networks → Tunnels
   - Create tunnel → Install `cloudflared`

2. **Add Public Hostnames**:
   - Tunnel → Public Hostname → Add
   - For each service:
     - Subdomain: `gitea`, `clickhouse`, `grafana`
     - Domain: `quadtech.dev`
     - Service: `http://localhost:3000` (or K8s service)

3. **Automatic DNS Records**:
   - Cloudflare automatically creates DNS records
   - All point to Cloudflare's network
   - No need to manage DNS manually

## Security Considerations

### Advantages
- ✅ **No exposed ports** - All inbound via Cloudflare Tunnel
- ✅ **DDoS protection** - Cloudflare handles it
- ✅ **Automatic TLS** - Managed by Cloudflare
- ✅ **Access policies** - Can add Cloudflare Access

### Considerations
- ⚠️ **Single point of failure** - If Cloudflare is down, services unavailable
- ⚠️ **Cloudflare can see traffic** - Consider end-to-end encryption for sensitive data
- ⚠️ **Tunnel dependency** - `cloudflared` must be running

### Recommended: Add Cloudflare Access

Protect services with additional authentication:

```yaml
# Cloudflare Zero Trust → Access → Applications
# Add application for each service
# Require authentication before accessing
```

## Updated Deployment Steps

### 1. Configure Cloudflare Tunnel

**On backbone-01:**

```sh
# If tunnel not created yet
cloudflared tunnel create quadnix

# Copy credentials
sudo mkdir -p /etc/cloudflared
sudo cp ~/.cloudflared/<tunnel-id>.json /etc/cloudflared/credentials.json

# Create config
sudo tee /etc/cloudflared/config.yml <<EOF
tunnel: <your-tunnel-id>
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: gitea.quadtech.dev
    service: http://localhost:3000
  - hostname: clickhouse.quadtech.dev
    service: http://localhost:8123
  - hostname: grafana.quadtech.dev
    service: http://localhost:3000
  - service: http_status:404
EOF

# Route DNS (in Cloudflare dashboard or via CLI)
cloudflared tunnel route dns quadnix gitea.quadtech.dev
cloudflared tunnel route dns quadnix clickhouse.quadtech.dev
cloudflared tunnel route dns quadnix grafana.quadtech.dev
```

### 2. Deploy Services

#### NixOS Services:
```sh
sudo nixos-rebuild switch --flake .#backbone-01
```

Services run on localhost, Cloudflare Tunnel exposes them.

#### Kubernetes Services:
```sh
# Deploy with adjusted Helm values (ClusterIP, no TLS)
nix build .#helmCharts.x86_64-linux.all.gitea
helm install gitea ./result/*.tgz -n gitea
```

### 3. Update Cloudflared Service

Make sure `cloudflared` points to the right services:

```nix
# modules/services/cloudflared-k8s.nix
# Ensure config.json is up to date
```

Or for Kubernetes services:

```yaml
ingress:
  - hostname: gitea.quadtech.dev
    service: http://gitea.gitea.svc.cluster.local:3000
```

### 4. Verify

```sh
# Check tunnel status
cloudflared tunnel info quadnix

# Check service accessibility
curl https://gitea.quadtech.dev
curl https://clickhouse.quadtech.dev
```

## Simplified Architecture Recommendation

Given you have Cloudflare Tunnel, here's my **recommended approach**:

### Use Cloudflare Tunnel → Direct to Services (Skip Ingress)

**Why:**
- ✅ Simpler - No ingress controller needed
- ✅ Fewer components to manage
- ✅ Lower resource usage
- ✅ Cloudflare handles all routing and TLS

**Configuration:**

```nix
# modules/roles/backbone.nix - NixOS Services
{
  imports = [
    ../services/gitea.nix
    ../services/clickhouse.nix
  ];
}
```

```yaml
# /etc/cloudflared/config.yml
tunnel: <id>
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: gitea.quadtech.dev
    service: http://localhost:3000
  - hostname: clickhouse.quadtech.dev
    service: http://localhost:8123
  - service: http_status:404
```

**Result:**
- Services accessible at `https://gitea.quadtech.dev`, etc.
- No ingress, no cert-manager, no LoadBalancer needed
- Cloudflare handles everything external

## Summary

**Impact of Cloudflare Tunnel:**

| Component | Without Cloudflare | With Cloudflare Tunnel |
|-----------|-------------------|----------------------|
| Public IP | Required | NOT needed |
| LoadBalancer | Required | NOT needed |
| Ingress Controller | Recommended | Optional |
| cert-manager | Required for TLS | NOT needed |
| Let's Encrypt | Required | NOT needed |
| Firewall Rules | 80, 443, etc. | Only 22 (SSH) |
| DNS Management | Manual/External DNS | Cloudflare automatic |
| TLS Certificates | Self-managed | Cloudflare managed |

**Recommended Setup:**
1. ✅ Use Cloudflare Tunnel → Direct to services
2. ✅ Skip ingress-nginx (unless you need complex routing)
3. ✅ Skip cert-manager (Cloudflare handles TLS)
4. ✅ Use ClusterIP services (NOT LoadBalancer)
5. ✅ Minimal firewall rules

This is **much simpler** than the full Kubernetes ingress setup! 🎉

## Files to Update

I'll create updated configurations that account for Cloudflare Tunnel...
