# Headscale Research & Design Document

**Date:** 2026-05-19
**Status:** Research Complete — Awaiting User Decisions
**Scope:** Self-hosted VPN alternative to Tailscale for remote admin access

---

## TL;DR Recommendation

**Deploy Headscale + WireGuard fallback.**

Headscale replaces the Tailscale control plane while keeping the same official Tailscale clients on all machines. This gives you DERP relay, MagicDNS, ACLs, and easy client onboarding — without vendor lock-in. A native WireGuard listener on backbone-01 (UDP 51820) provides a dead-man's fallback that requires zero dependencies.

**Do not remove Cloudflare Tunnels** — they continue to serve HTTP ingress for public services. This research is only about the VPN/admin access layer.

---

## 1. Current State Analysis

| Component | Role | Status |
|---|---|---|
| Tailscale (profiles/tailscale.nix) | VPN mesh for remote admin (backbone-01 only currently) | Active, auth key in SOPS |
| Cloudflare Tunnel | HTTP ingress (Forgejo, ArgoCD, Harbor, etc.) + SSH via `f1.quadtech.dev` | Active, stays |
| frontline-01 | Kubernetes worker node | No Tailscale currently |
| backbone-01 | Kubernetes control plane + services | Tailscale enabled as subnet router |

**Risk:** If Tailscale changes pricing/terms or their control plane has an outage, you lose remote VPN access to your infra. Cloudflare Tunnels also have a hard dependency for SSH access.

---

## 2. Technology Overview

### 2.1 WireGuard (Native NixOS)

**What it is:** Layer 3 VPN tunnel protocol built into the Linux kernel. No control plane — you manually configure peers, IPs, and routes.

**NixOS module:** `networking.wireguard` (part of nixpkgs)

```nix
# Example: WireGuard server on backbone-01
networking.wireguard.interfaces.wg0 = {
  ips = [ "10.10.0.1/24" ];
  listenPort = 51820;
  privateKeyFile = "/run/secrets/wireguard-private-key";
  
  peers = [
    {
      # Benjamin's laptop
      publicKey = "..." ;
      allowedIPs = [ "10.10.0.2/32" ];
    }
    {
      # Additional device
      publicKey = "...";
      allowedIPs = [ "10.10.0.3/32" ];
    }
  ];
};

networking.firewall.allowedUDPPorts = [ 51820 ];
```

| Aspect | Detail |
|---|---|
| **Setup complexity** | Low for 2-3 peers. Scales poorly to many devices. |
| **Client onboarding** | Manual: generate keypair, exchange public keys, configure IPs |
| **Relay/fallback** | None. If direct UDP is blocked, connection fails. |
| **Vendor dependency** | Zero. In-kernel. |
| **Cost** | Free |
| **NixOS support** | First-class `networking.wireguard` module |
| **MagicDNS** | No |
| **ACLs** | Firewall rules only (iptables/nftables) |
| **Subnet routing** | Manual via `allowedIPs` and `postUp` commands |

### 2.2 Tailscale (Current)

| Aspect | Detail |
|---|---|
| **Setup complexity** | Trivial — install, `tailscale up`, auth via browser |
| **Client onboarding** | Single command, OIDC auth |
| **Relay/fallback** | Tailscale DERP servers (global, free) |
| **Vendor dependency** | **Full** — control plane is Tailscale-owned SaaS |
| **Cost** | Free tier (up to 100 devices, 3 users) |
| **MagicDNS** | Yes (via Tailscale DNS) |
| **ACLs** | HuJSON policy file in Tailscale admin |
| **Subnet routing** | Built-in (`--advertise-routes`) |

### 2.3 Headscale

**What it is:** Open-source reimplementation of the Tailscale coordination server. Same WireGuard-based mesh, same official Tailscale clients — just a different control plane URL.

| Aspect | Detail |
|---|---|
| **Setup complexity** | Medium — deploy server, configure DNS, enroll clients with `--login-server` |
| **Client onboarding** | Pre-auth keys or OIDC. Same `tailscale up` but pointed at your server |
| **Relay/fallback** | Embedded DERP server (or use Tailscale's public DERPs) |
| **Vendor dependency** | **Zero** — you run the control plane |
| **Cost** | Free (self-hosted) |
| **MagicDNS** | Yes (via Headscale DNS config) |
| **ACLs** | HuJSON policy file or database-backed |
| **Subnet routing** | Same as Tailscale — `--advertise-routes` works |
| **Data store** | SQLite (default) or PostgreSQL |
| **Admin UI** | Headplane (3rd party) or CLI |
| **K8s deployment** | gabe565 Helm chart (well-maintained) |
| **NixOS module** | First-class `services.headscale` in nixpkgs |

---

## 3. Comparison Table

| | WireGuard | Tailscale | Headscale |
|---|---|---|---|
| **Setup complexity** | Low (2 peers) / High (many) | Trivial | Medium |
| **Client onboarding** | Manual key exchange | 1 command + browser | 1 command + pre-auth key / OIDC |
| **Relay when direct fails** | ❌ None | ✅ Global DERP | ✅ Embedded DERP |
| **MagicDNS** | ❌ | ✅ | ✅ |
| **ACLs / policy** | Firewall only | HuJSON policy | HuJSON policy |
| **Subnet routing** | Manual iptables | Built-in | Built-in |
| **Vendor dependency** | None | Full (SaaS control plane) | None (self-hosted) |
| **Cost** | Free | Free tier (100 devices) | Free (your infra) |
| **Phone client** | WireGuard app | Tailscale app | Tailscale app (same!) |
| **macOS client** | WireGuard app | Tailscale app | Tailscale app (same!) |
| **NixOS module** | `networking.wireguard` | `services.tailscale` | `services.headscale` |
| **Offline resilience** | ✅ Works without server | ❌ Needs control plane | ❌ Needs control plane |
| **Audit surface** | Minimal | Large (SaaS) | Medium (your server) |

**Key insight:** Headscale gives you 90% of Tailscale's UX with zero vendor dependency. The only gap is that Headscale's control plane must be reachable for new connections (existing WireGuard tunnels survive brief outages).

---

## 4. Recommended Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    INTERNET                              │
├─────────────────────────────────────────────────────────┤
│  Cloudflare Tunnel ──► HTTP services (stays as-is)      │
│                                                          │
│  vpn.quadtech.dev ──► Headscale (K8s, namespace: vpn)   │
│       │                    │                              │
│       │                    ├── Embedded DERP (TCP/HTTPS) │
│       │                    └── STUN (UDP/3478)           │
│       │                                                   │
│  UDP/51820 ──► WireGuard fallback (backbone-01 host)     │
└─────────────────────────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
   ┌────────────┐  ┌────────────┐  ┌──────────┐
   │ backbone-01│  │frontline-01│  │ Laptop   │
   │ ts client  │  │ ts client  │  │ts client │
   │ wg server  │  │            │  │wg client │
   └────────────┘  └────────────┘  └──────────┘
```

### Layers:

1. **Primary VPN:** Headscale (K8s deployment) → Tailscale clients connect to `vpn.quadtech.dev`
2. **Fallback VPN:** WireGuard on backbone-01 (host-level) → direct UDP/51820
3. **HTTP ingress:** Cloudflare Tunnel (unchanged)

---

## 5. NixOS Module Design

### 5.1 Headscale Profile — `modules/profiles/headscale-client.nix`

This replaces `profiles/tailscale.nix` (or coexists during migration):

```nix
# modules/profiles/headscale-client.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.quadnix.headscale-client;
in {
  options.services.quadnix.headscale-client = {
    enable = lib.mkEnableOption "Headscale VPN client";

    loginServer = lib.mkOption {
      type = lib.types.str;
      default = "https://vpn.quadtech.dev";
      description = "Headscale control server URL";
    };

    advertiseRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Subnet routes to advertise (e.g. [\"192.168.1.0/24\"])";
    };

    acceptRoutes = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Accept subnet routes from other nodes";
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";  # subnet router + relay
      authKeyFile = "/run/secrets/headscale-auth-key";
      extraUpFlags = [
        "--login-server=${cfg.loginServer}"
      ] ++ lib.optionals (cfg.advertiseRoutes != []) [
        "--advertise-routes=${lib.concatStringsSep "," cfg.advertiseRoutes}"
      ] ++ lib.optionals cfg.acceptRoutes [
        "--accept-routes"
      ];
    };

    networking.firewall.allowedUDPPorts = [ 41641 ];
  };
}
```

### 5.2 WireGuard Fallback — `modules/profiles/wireguard-fallback.nix`

```nix
# modules/profiles/wireguard-fallback.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.quadnix.wireguard-fallback;
in {
  options.services.quadnix.wireguard-fallback = {
    enable = lib.mkEnableOption "WireGuard fallback VPN server";

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 51820;
    };

    subnet = lib.mkOption {
      type = lib.types.str;
      default = "10.10.0.0/24";
    };

    serverIp = lib.mkOption {
      type = lib.types.str;
      default = "10.10.0.1/24";
    };

    peers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          publicKey = lib.mkOption { type = lib.types.str; };
          allowedIPs = lib.mkOption { type = lib.types.listOf lib.types.str; };
        };
      });
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    networking.wireguard.interfaces.wg0 = {
      ips = [ cfg.serverIp ];
      listenPort = cfg.listenPort;
      privateKeyFile = "/run/secrets/wireguard-private-key";

      peers = map (p: {
        inherit (p) publicKey;
        allowedIPs = p.allowedIPs;
      }) cfg.peers;
    };

    networking.firewall.allowedUDPPorts = [ cfg.listenPort ];
  };
}
```

### 5.3 Backbone Role Integration

In `modules/roles/backbone.nix`, replace:

```nix
# FROM:
../profiles/tailscale.nix

# TO (after migration):
../profiles/headscale-client.nix
../profiles/wireguard-fallback.nix
```

And configure in the host file:

```nix
services.quadnix.headscale-client = {
  enable = true;
  advertiseRoutes = [ "192.168.1.0/24" ];  # Expose LAN via VPN
};

services.quadnix.wireguard-fallback = {
  enable = true;
  peers = [
    {
      name = "benjamin-laptop";
      publicKey = "<LAPTOP_PUBKEY>";
      allowedIPs = [ "10.10.0.2/32" ];
    }
  ];
};
```

### 5.4 Frontline Role Integration

```nix
# modules/roles/frontline.nix — add:
../profiles/headscale-client.nix

# Configure in host:
services.quadnix.headscale-client = {
  enable = true;
  acceptRoutes = true;
};
```

---

## 6. K8s Deployment — Headscale

### 6.1 Chart: gabe565/headscale

The [gabe565 Helm chart](https://charts.gabe565.com/charts/headscale/) is well-maintained and uses the bjw-s common library. It supports environment variable-based configuration.

**Chart details:**
- Repository: `https://charts.gabe565.com`
- Chart: `headscale`
- Latest version: `0.16.x` (tracking Headscale 0.24+)
- Features: PVC for SQLite, embedded DERP support, ingress, init containers

### 6.2 New Chart File — `lib/helm/charts/headscale.nix`

```nix
{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://charts.gabe565.com";
    chart = "headscale";
    version = "0.16.0";  # Verify latest before deploying
    chartHash = "sha256-PLACEHOLDER";  # nix-prefetch-url after first attempt
  };
in {
  headscale = helmLib.buildChart {
    name = "headscale";
    inherit chart;
    namespace = "vpn";
    values = {
      # --- Controller image ---
      image = {
        repository = "headscale/headscale";
        tag = "0.24.2";  # Match with chart compatibility
      };

      # --- Environment variables (Headscale config via env) ---
      env = {
        HEADSCALE_SERVER_URL = "https://vpn.quadtech.dev";
        HEADSCALE_LISTEN_ADDR = "0.0.0.0:8080";
        HEADSCALE_METRICS_LISTEN_ADDR = "0.0.0.0:9090";
        HEADSCALE_DATABASE_TYPE = "sqlite";
        HEADSCALE_DATABASE_SQLITE_PATH = "/data/headscale.db";
        HEADSCALE_DNS_BASE_DOMAIN = "tail.quadtech.dev";
        HEADSCALE_DNS_NAMESERVERS_GLOBAL = "1.1.1.1,1.0.0.1";
        HEADSCALE DERP_SERVER_ENABLED = "true";
        HEADSCALE_DERP_SERVER_REGION_ID = "900";
        HEADSCALE_DERP_SERVER_REGION_CODE = "quadtech";
        HEADSCALE_DERP_SERVER_REGION_NAME = "QuadTech DERP";
        HEADSCALE_DERP_SERVER_STUN_LISTEN_ADDR = "0.0.0.0:3478";
        HEADSCALE_DERP_SERVER_LISTEN_ADDR = "0.0.0.0:443";
      };

      # --- Persistence for SQLite database ---
      persistence = {
        data = {
          enabled = true;
          mountPath = "/data";
          storageClass = "ceph-block";
          size = "1Gi";
          accessMode = "ReadWriteOnce";
        };
      };

      # --- Ingress for API / admin ---
      ingress = {
        main = {
          enabled = true;
          className = "nginx";
          annotations = {
            "nginx.ingress.kubernetes.io/ssl-redirect" = "false";
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
          };
          hosts = [
            {
              host = "vpn.quadtech.dev";
              paths = [
                { path = "/"; }
              ];
            }
          ];
        };
      };

      # --- Service ---
      service = {
        main = {
          type = "NodePort";
          ports = {
            http = {
              port = 8080;
              targetPort = 8080;
            };
          };
        };
        stun = {
          enabled = true;
          type = "NodePort";
          ports = {
            stun = {
              port = 3478;
              targetPort = 3478;
              protocol = "UDP";
            };
          };
        };
      };

      # --- Resources ---
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
        limits = {
          cpu = "500m";
          memory = "512Mi";
        };
      };
    };
  };
}
```

### 6.3 Bootstrap Integration

Add to `lib/helm/charts/default.nix`:

```nix
headscale = import ./headscale.nix { inherit helmLib; };

# In the attrset:
inherit (headscale) headscale;
```

Add to `modules/outputs/bootstrap.nix` alongside other ArgoCD-managed apps, or deploy directly via the bootstrap manifests.

### 6.4 ArgoCD Application (if using GitOps)

```nix
# Using composable library
composable.mkArgoHelmApp {
  name = "headscale";
  namespace = "vpn";
  chart = "headscale";
  repoURL = "https://charts.gabe565.com";
  targetRevision = "0.16.x";
  values = "";  # Or inline values
}
```

Or manage via ArgoCD app-of-apps pattern (consistent with existing `argocd-apps.nix`).

---

## 7. Migration Plan

### Phase 0: Preparation (No Disruption)
1. Deploy Headscale in K8s namespace `vpn` with gabe565 chart
2. Configure `vpn.quadtech.dev` DNS → Cloudflare Tunnel → Headscale service
3. Generate Headscale pre-auth key
4. Set up ACL policy file (start permissive, tighten later)
5. Enable embedded DERP server
6. Add `headscale-auth-key` to SOPS secrets

### Phase 1: Dual-Stack (Coexistence)
1. Create `modules/profiles/headscale-client.nix` profile
2. Add profile to backbone-01 config alongside existing `tailscale.nix`
3. Tailscale daemon connects to both control planes simultaneously
   - **IMPORTANT:** Tailscale client can only connect to ONE control plane at a time
   - The solution: run a SECOND tailscale instance for Headscale during migration
   - OR: switch backbone-01 to Headscale first (lowest risk — can revert)
4. Test connectivity via Headscale IP
5. Enroll laptop: `tailscale up --login-server=https://vpn.quadtech.dev`
6. Verify LAN access through Headscale subnet route

### Phase 2: Switch Over
1. Enroll frontline-01 with Headscale
2. Update `profiles/tailscale.nix` → `profiles/headscale-client.nix` in roles
3. Remove Tailscale auth key dependency
4. Verify all connectivity works through Headscale
5. Set up WireGuard fallback on backbone-01

### Phase 3: Cleanup
1. Remove Tailscale SaaS account (or keep as cold standby)
2. Remove `profiles/tailscale.nix` from repo
3. Remove `tailscale-auth-key` from SOPS
4. Tighten ACLs in Headscale policy
5. Set up Headscale SQLite backup (cron job or K8s CronJob)

### Migration Gotcha: Single Control Plane Per Client

The official Tailscale client connects to exactly one control plane. You **cannot** be on both Tailscale and Headscale simultaneously with the same `tailscaled` instance. Migration strategies:

**Option A (Recommended): Per-machine cutover**
- Stop `tailscaled` on a machine
- Reconfigure to point at Headscale
- `tailscale up --login-server=https://vpn.quadtech.dev`
- Downtime: ~30 seconds per machine

**Option B: Second tailscaled instance**
- Run a second `tailscaled` with `--socket=/var/run/tailscale-headscale.sock`
- More complex, more risk, not worth it for 2-3 machines

---

## 8. SOPS Secrets Required

Add to `secrets/backbone-01.yaml`:

```yaml
headscale-auth-key: ENC[AES256_GCM,data:...,tag:...]
wireguard-private-key: ENC[AES256_GCM,data:...,tag:...]
```

In `modules/hosts/backbone-01.nix`:

```nix
sops.secrets = {
  headscale-auth-key = {
    sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    path = "/run/secrets/headscale-auth-key";
    owner = "root";
    group = "root";
    mode = "0400";
  };
  wireguard-private-key = {
    sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    path = "/run/secrets/wireguard-private-key";
    owner = "root";
    group = "root";
    mode = "0400";
  };
};
```

---

## 9. Headscale ACL Policy

Example policy file (`secrets/headscale-acl.hujson` or ConfigMap):

```json
{
  "groups": {
    "group:admin": ["benjamin@quadtech.dev"]
  },
  "acls": [
    // Admins can access everything
    {"action": "accept", "src": ["group:admin"], "dst": ["*:*"]},
    // Nodes can reach each other
    {"action": "accept", "src": ["tag:server"], "dst": ["tag:server:*"]}
  ],
  "tagOwners": {
    "tag:server": ["group:admin"]
  },
  "autoApprovers": {
    "routes": {
      "192.168.1.0/24": ["tag:server"]
    }
  }
}
```

---

## 10. WireGuard Client Config (Fallback)

For the laptop, a WireGuard client config as dead-man's switch:

```ini
# /etc/wireguard/wg0.conf (macOS via WireGuard app)
[Interface]
PrivateKey = <LAPTOP_PRIVATE_KEY>
Address = 10.10.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = <BACKBONE_PUBLIC_KEY>
Endpoint = backbone-01.local:51820  # Or public IP / DDNS
AllowedIPs = 10.10.0.0/24, 192.168.1.0/24
PersistentKeepalive = 25
```

---

## 11. Open Questions for User

### Must Decide Before Implementation

1. **Helm chart vs raw manifests?**
   - gabe565 Helm chart (recommended — follows existing pattern)
   - Raw K8s manifests via composable library
   - NixOS host-level deployment instead of K8s

2. **DERP strategy?**
   - Embedded DERP in Headscale (simplest, recommended)
   - Use Tailscale's public DERP servers as fallback
   - Both (embedded primary, Tailscale public as fallback)

3. **Admin UI?**
   - Headplane (most feature-complete, has NixOS module)
   - headscale-admin (lighter alternative)
   - CLI only (no web UI)

4. **ACL storage?**
   - File-based (`policy.path` in config) — version-controlled in Git
   - Database-backed — managed via API/UI

5. **Authentication for client enrollment?**
   - Pre-auth keys only (simplest, good for personal infra)
   - OIDC via an identity provider (Forgejo? Authelia?)
   - Both

6. **Should frontline-01 get Headscale too?**
   - Yes (full mesh, recommended)
   - No (only backbone-01 for now)

7. **SQLite backup strategy?**
   - K8s CronJob that copies `/data/headscale.db` to Ceph S3
   - Host-level cron on backbone-01
   - No backup (acceptable for personal infra?)

8. **DNS for Headscale endpoint?**
   - `vpn.quadtech.dev` via Cloudflare (needs tunnel route)
   - Direct public IP / DDNS hostname
   - `headscale.k8s.quadtech.dev` via existing ingress

9. **Cloudflare Tunnel for SSH access?**
   - Keep as-is alongside Headscale (belt and suspenders)
   - Remove SSH tunnel routes from cloudflared config once Headscale is stable

10. **Timing/priority?**
    - Implement now?
    - Queue for later sprint?

---

## 12. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Headscale control plane down | Low | Medium — new connections fail, existing tunnels survive | WireGuard fallback |
| SQLite corruption | Low | Medium — lose node registry | Regular backups |
| DERP relay unreachable | Low | Low — direct WireGuard usually works | Use Tailscale public DERPs as fallback |
| Headscale project abandoned | Low | Medium — switch back to Tailscale or use WireGuard | WireGuard fallback always available |
| Migration breaks access | Medium | High — locked out of infra | Keep Cloudflare SSH tunnel during migration |

---

## 13. Files to Create/Modify (Implementation Phase)

### New Files
```
modules/profiles/headscale-client.nix     # Headscale VPN client profile
modules/profiles/wireguard-fallback.nix   # WireGuard fallback profile
lib/helm/charts/headscale.nix             # Headscale Helm chart definition
secrets/headscale-acl.hujson              # ACL policy
```

### Modified Files
```
lib/helm/charts/default.nix               # Add headscale chart
lib/helm/repositories.nix                 # Add gabe565 repo
modules/roles/backbone.nix                # Switch profiles
modules/hosts/backbone-01.nix             # Add SOPS secrets + config
modules/roles/frontline.nix               # Add headscale profile
secrets/backbone-01.yaml                  # Add headscale-auth-key + wireguard keys
lib/cloudflared-config.nix                # Add vpn.quadtech.dev route (optional)
```

### Optionally Removed (After Migration)
```
modules/profiles/tailscale.nix            # Replaced by headscale-client.nix
```

---

## 14. References

- [Headscale official docs](https://headscale.net/)
- [Headscale GitHub](https://github.com/juanfont/headscale)
- [gabe565 Helm chart](https://charts.gabe565.com/charts/headscale/)
- [Headplane admin UI](https://github.com/tale/headplane)
- [Headscale DERP docs](https://headscale.net/stable/ref/derp/)
- [Headscale ACL docs](https://headscale.net/stable/ref/acls/)
- [NixOS headscale module options](https://search.nixos.org/options?show=headscale)
- [Headscale on NixOS guide (NotAShelf)](https://notashelf.dev/posts/using-headscale)
- [NixOS Wiki: WireGuard](https://nixos.wiki/wiki/WireGuard)
