# Phase 3: Add Real Frontline-01 Host

## Objective
Provision a real frontline-01 machine as a K8s worker node, wire it into the cluster, and verify multi-host cloudflared connectivity.

## Prerequisites
- Phase 1 complete (cloudflared deduplicated)
- Phase 2 complete (host abstraction generalized)
- Physical/virtual machine available for frontline-01
- Network connectivity between frontline-01 and backbone-01

## Plan

### Step 1: Generate hardware config

On the new frontline-01 machine:
```bash
nixos-generate-config --root /mnt
# Copy /mnt/etc/nixos/hardware-configuration.nix → modules/hardware/frontline-01.nix
```

Update `modules/hardware/frontline-01.nix` with real UUIDs, filesystem layout, and boot configuration.

### Step 2: Configure host module

Update `modules/hosts/frontline-01.nix`:
```nix
{ config, ... }:
{
  quad.hosts.frontline-01 = {
    system = "x86_64-linux";
    role = "frontline";
    hardwareModule = ../hardware/frontline-01.nix;
    k8s = {
      masterAddress = "backbone-01.local";
      labels = { "node-role.kubernetes.io/worker" = ""; };
    };
  };
}
```

### Step 3: Create per-host secrets

```bash
# On the new host, generate sops key
sops --age-key /etc/sops/keys.txt -d secrets/frontline-01.yaml
```

Minimal secrets for frontline:
- SSH authorized keys (already in base profile)
- Sops age key for secret decryption
- Kubelet client certs (handled by easyCerts if joining same cluster)

### Step 4: Cloudflared multi-host strategy

With two hosts, cloudflared needs consideration:

**Option A: Keep cloudflared on backbone-01 only (recommended)**
- Simplest: cloudflared stays on backbone-01 (host systemd + K8s deployment)
- frontline-01 only needs cluster networking (flannel)
- No cloudflared changes needed

**Option B: Cloudflared on both hosts**
- Redundancy: if backbone-01 goes down, frontline-01 keeps the tunnel alive
- Requires: separate tunnel or shared tunnel with both hosts as replicas
- More complex: need to ensure routes point to the right host

**Recommendation**: Start with Option A. The shared `cloudflared-routes.nix` from Phase 1 makes it easy to add Option B later.

### Step 5: Network configuration

Ensure frontline-01 can reach:
- `backbone-01.local:6443` (K8s API)
- `backbone-01.local:2379` (etcd, via flannel)
- MetalLB IP `192.168.1.240` (ingress)
- `10.0.0.56:5000` (Harbor registry) — or via ingress

Add to `modules/roles/frontline.nix`:
```nix
networking.hosts."192.168.1.240" = [ "harbor.quadtech.dev" ];
```

### Step 6: Deploy and verify

1. Build: `nix build .#nixosConfigurations.frontline-01.config.system.build.toplevel`
2. Deploy: `nix run github:serokell/deploy-rs -- .#frontline-01 --skip-checks`
3. Verify:
   ```bash
   kubectl get nodes  # should show frontline-01 as Ready
   kubectl get pods -A -o wide  # some pods should schedule on frontline-01
   ```

### Step 7: Update deploy.nix

Ensure `frontline-01` entry in `modules/outputs/deploy.nix` has the correct hostname/IP.

## Cloudflared Considerations (from memory)

Per MEMORY.md:
- **TWO cloudflared instances** currently: host systemd (backbone.nix) + K8s deployment (bootstrap.nix)
- Host cloudflared routes to `127.0.0.1:30856` (NodePort → ingress) ✅
- K8s cloudflared routes to `127.0.0.1:80` (bug from Phase 1, now fixed)
- Both use same tunnel ID `b6bac523-be70-4625-8b67-fa78a9e1c7a5`
- Cloudflare load-balances between instances

With frontline-01 added:
- The K8s cloudflared pod might land on frontline-01 (uses `hostNetwork: true`)
- Need to ensure the K8s cloudflared routes work from ANY node, not just backbone-01
- `127.0.0.1:30856` works on any node (NodePort is cluster-wide)
- This is fine — no changes needed after Phase 1 fix

## Files Changed

| File | Action |
|------|--------|
| `modules/hardware/frontline-01.nix` | **Replace** — real hardware config |
| `modules/hosts/frontline-01.nix` | **Modify** — real config with options |
| `secrets/frontline-01.yaml` | **Create** — per-host sops secrets |
| `modules/roles/frontline.nix` | **Modify** — add harbor hosts entry, ensure networking |
| `modules/outputs/deploy.nix` | **Verify** — correct IP/hostname for frontline-01 |

## Estimated Complexity
**Medium** — depends on physical machine setup and network configuration.
