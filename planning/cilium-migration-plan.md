# Cilium Migration Plan — Flannel → Cilium

## Current State

| Component | Details |
|-----------|---------|
| **CNI** | Flannel (systemd, etcd backend, custom ExecStart) |
| **kube-proxy** | NixOS kubernetes module (iptables mode) |
| **K8s version** | 1.36.1 (nixpkgs), `clusterCidr = 10.1.0.0/16` (NixOS default) |
| **Nodes** | backbone-01 (control-plane + workloads), frontline-01 (worker) |
| **Pod CIDR** | `10.1.0.0/16` (default from NixOS module) |
| **Service CIDR** | Default K8s range |
| **Flannel config** | Custom systemd unit — uses etcd directly with TLS, binds to `enp0s31f6` |
| **Helm infra** | nixhelm + nix-kube-generators for declarative Helm renders |
| **ArgoCD** | Manages in-cluster apps (Harbor, Forgejo, monitoring, etc.) |

## Target State

| Component | Details |
|-----------|---------|
| **CNI** | Cilium (DaemonSet via Helm) |
| **kube-proxy** | **Removed** — Cilium replaces it entirely (eBPF) |
| **NetworkPolicy** | Enabled (Cilium supports full K8s NetworkPolicy v1 + extended policies) |
| **Hubble** | Optional — observability layer (can enable later) |

## Why Cilium?

1. **eBPF kube-proxy replacement** — lower latency, fewer iptables rules
2. **NetworkPolicy support** — flannel has none
3. **Better observability** — Hubble provides flow logs, service maps, metrics
4. **Cluster Mesh ready** — future multi-cluster if needed
5. **Transparent encryption** — WireGuard-based pod-to-pod encryption available
6. **Active community** — CNCF graduated project, rapid updates

---

## Prerequisites

### 1. Kernel Requirements

Cilium requires BPF / eBPF kernel support. Check on both nodes:

```bash
# On each node (via SSH or deploy):
ssh backbone01 "uname -r"
ssh backbone01 "grep -c CONFIG_BPF /boot/config-\$(uname -r)"
ssh backbone01 "ls /sys/fs/bpf"  # should exist (bpffs)
```

**Minimum kernel**: 5.4+ for basic Cilium. **5.10+ recommended** for kube-proxy replacement.
NixOS unstable should ship 6.x — verify.

If `CONFIG_BPF` is missing, add to `modules/profiles/base.nix` or `modules/hardware/*.nix`:
```nix
boot.kernelModules = [ "bpf" ];
# The NixOS default kernel already includes BPF — likely no changes needed.
```

### 2. Etcd Health

Flannel uses etcd directly. Cilium uses the Kubernetes API for state. Before migrating:
```bash
kubectl get cs  # ensure etcd is healthy
```

### 3. Backups

```bash
# Snapshot etcd
ssh backbone01 'ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/kubernetes/secrets/ca.pem \
  --cert=/var/lib/kubernetes/secrets/kubernetes.pem \
  --key=/var/lib/kubernetes/secrets/kubernetes-key.pem \
  snapshot save /var/lib/etcd/snapshot-pre-cilium.db'

# Export all workloads (belt & suspenders)
kubectl get all -A -o yaml > cluster-backup-pre-cilium.yaml
```

---

## Migration Strategy: Blue-Green CNI Swap

Because you only have 2 nodes and both run workloads, the safest approach is a **brief maintenance window** with a full CNI swap. A node-by-node rolling migration is possible but complex with only 2 nodes.

### Option A: Maintenance Window (Recommended for 2-node cluster)

Simplest and safest. ~5-10 min of pod networking downtime.

1. **Announce maintenance** — scale down any critical workloads gracefully
2. **Deploy to all nodes simultaneously** — swap flannel → cilium in NixOS config + apply
3. **Cilium DaemonSet boots** — takes over networking
4. **Validate** — confirm pods can communicate, services resolve
5. **Remove kube-proxy** — switch to eBPF replacement

### Option B: Node-by-Node Rolling (Complex, Not Recommended for 2 Nodes)

Possible but requires a "dual CNI" period where both flannel and cilium are active. Only makes sense for clusters with many nodes.

**Going with Option A.**

---

## Implementation Steps

### Phase 1: Prepare Cilium Helm Chart in Nix

#### 1a. Add Cilium chart to nixhelm

Cilium is already available in nixhelm. Verify:
```bash
nix eval .#chartsDerivations.x86_64-linux --apply 'x: builtins.attrNames (builtins.filterAttrs (n: _: builtins.match ".*cilium.*" n != null) x)' --json
```

If not present, you may need to update the nixhelm flake input or add it manually.

#### 1b. Create `lib/helm/charts/cilium.nix`

```nix
{helmLib}: let
  cilium = helmLib.buildChart {
    name = "cilium";
    chart = helmLib.charts.cilium.cilium;
    namespace = "kube-system";
    values = {
      # Use K8s CRDs for state (not etcd)
      etcd = {
        enabled = false;
      };
      
      # Replace kube-proxy entirely
      kubeProxyReplacement = "strict";
      
      # Since we're doing a fresh install (no kube-proxy), use Helm install 
      # time detection
      kubeProxyReplacementHealthzBindAddr = "";
      
      # Pod CIDR — must match clusterCidr
      ipam = {
        mode = "kubernetes";
      };
      
      # Enable Hubble (optional — can disable for initial migration)
      hubble = {
        enabled = false;  # Enable after migration is stable
      };
      
      # Operator
      operator = {
        replicas = 1;
      };
      
      # Security context
      securityContext = {
        capabilities = {
          ciliumAgent = ["CHOWN" "KILL" "NET_ADMIN" "NET_RAW" "IPC_LOCK" "SYS_ADMIN" "SYS_RESOURCE" "DAC_OVERRIDE" "FOWNER" "SETGID" "SETUID"];
          cleanCiliumState = ["NET_ADMIN" "SYS_ADMIN" "SYS_RESOURCE"];
        };
      };
      
      # Cgroup path for containerd
      cgroup = {
        autoMount = {
          enabled = false;
        };
        hostRoot = "/sys/fs/cgroup";
      };
      
      # Tunnel mode (VXLAN — simplest, no BGP, works everywhere)
      tunnel = "vxlan";
      
      # Don't manage kube-proxy — we're removing it
      nodeinit = {
        enabled = false;  # NixOS handles node initialization
      };
    };
  };
in {
  inherit cilium;
}
```

#### 1c. Register in `lib/helm/charts/default.nix`

Add:
```nix
cilium = import ./cilium.nix {inherit helmLib;};
```
And in the attrset:
```nix
inherit (cilium) cilium;
```

#### 1d. Create bootstrap manifest `modules/outputs/bootstrap/cilium.nix`

```nix
{lib, inputs, ...}: let
  shared = import ./shared.nix {inherit lib inputs;};
in {
  options.services.quadnix.bootstrap.cilium = lib.mkEnableOption "Cilium CNI bootstrap manifest";

  config = lib.mkIf config.services.quadnix.bootstrap.cilium {
    # Wire to the bootstrap render pipeline
    # (Follow the pattern from ingress-nginx.nix or metallb.nix)
  };
}
```

### Phase 2: Modify NixOS Modules — Disable Flannel & kube-proxy

#### 2a. Create `modules/profiles/kubernetes/cilium.nix`

```nix
{config, lib, pkgs, ...}: {
  # Signal that we're using Cilium (not flannel)
  services.kubernetes.flannel.enable = lib.mkForce false;
  
  # Disable kube-proxy — Cilium replaces it
  services.kubernetes.proxy.enable = lib.mkForce false;
  
  # Cilium needs these kernel modules
  boot.kernelModules = [
    "bpfilter"
    "veth"
    "bridge"
    "bridge-netfilter"
    "ip6_tables"
    "ip6table_nat"
    "ip6table_mangle"
    "ip6table_raw"
    "ip6table_filter"
    "iptable_nat"
    "iptable_mangle"
    "iptable_raw"
    "iptable_filter"
    "ip_tables"
    "nf_conntrack"
    "nf_conntrack_netlink"
    "nf_defrag_ipv4"
    "nf_defrag_ipv6"
    "nf_nat"
    "nf_reject_ipv4"
    "nf_reject_ipv6"
    "nf_tables"
    "nft_compat"
    "x_tables"
    "xt_addrtype"
    "xt_conntrack"
    "xt_mark"
    "xt_multiport"
    "xt_nat"
    "xt_pkttype"
    "xt_socket"
    "xt_string"
    "xt_tcpudp"
    "xt_TIME"
    "xt_bpf"  # BPF programs for networking
  ];

  # Ensure /sys/fs/bpf is mounted (bpffs)
  boot.kernelParams = [
    "bpf.enable=1"  # Not strictly needed on 5.x+ but doesn't hurt
  ];

  # Open Cilium firewall ports
  networking.firewall.allowedTCPPorts = [
    4240   # Cilium health checks
  ];
  networking.firewall.allowedUDPPorts = [
    8472   # VXLAN (same port flannel used)
  ];

  # Remove flannel from systemPackages
  environment.systemPackages = with pkgs; [
    kubernetes
    kubectl
    cri-tools
    containerd
    cilium-cli  # Add cilium CLI for debugging
  ];
}
```

#### 2b. Modify `modules/profiles/kubernetes/control-plane.nix`

```nix
# Changes needed:
# 1. Remove flannelInterface let binding
# 2. Remove flannel from environment.systemPackages
# 3. Remove the entire systemd.services.flannel block
# 4. Remove the kube-proxy GODEBUG override (service disabled)
# 5. Add imports for cilium.nix
```

Specifically, remove:
- `flannelInterface = "enp0s31f6";` 
- `flannel` from `environment.systemPackages`
- The entire `systemd.services.flannel = { ... };` block
- `systemd.services.kube-proxy.environment.GODEBUG = "netdns=cgo";`

Add:
- Import `./cilium.nix`
- `pkgs.cilium-cli` to systemPackages

#### 2c. Modify `modules/profiles/kubernetes/worker.nix`

```nix
# Remove:
- systemd.services.kube-proxy.environment.GODEBUG = "netdns=cgo";

# Add:
- imports = [ ./cilium.nix ];
- pkgs.cilium-cli to environment.systemPackages (optional)
```

### Phase 3: Pre-Migration — Deploy Cilium DaemonSet (No-op)

Before touching the NixOS configs, render and inspect the Cilium manifest:

```bash
# Build the bootstrap output with cilium included
nix build .#bootstrapInfra.aarch64-darwin

# Inspect the Cilium manifest
cat result/cilium.yaml | head -50

# Validate the manifest
kubectl apply --dry-run=client -f result/cilium.yaml
```

### Phase 4: Migration Day

#### Step 1: Cordon frontline-01 (worker)

```bash
kubectl cordon frontline-01
kubectl drain frontline-01 --ignore-daemonsets --delete-emptydir-data
```

#### Step 2: Deploy Cilium CRDs first

```bash
# Apply CRDs before the DaemonSet
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/main/install/kubernetes/cilium/files/cilium-crds.yaml
```

Or bundle CRDs in the bootstrap manifest.

#### Step 3: Apply Cilium manifest

```bash
nix build .#bootstrapInfra.aarch64-darwin
kubectl apply -f result/cilium.yaml
```

Wait for Cilium pods to be Running:
```bash
kubectl -n kube-system rollout status ds/cilium --timeout=120s
```

#### Step 4: Deploy NixOS config to backbone-01

```bash
# This disables flannel and kube-proxy on the control plane
cd QuadNix && nix run github:serokell/deploy-rs -- .#backbone-01 --skip-checks
```

Wait for the node to come back. Cilium DaemonSet will start on backbone-01.

#### Step 5: Deploy NixOS config to frontline-01

```bash
nix run github:serokell/deploy-rs -- .#frontline-01 --skip-checks
```

#### Step 6: Uncordon frontline-01

```bash
kubectl uncordon frontline-01
```

#### Step 7: Validate

```bash
# Cilium status
cilium status

# All nodes ready
kubectl get nodes -o wide

# All pods running
kubectl get pods -A -o wide

# Test pod-to-pod connectivity
kubectl run test-net --image=busybox --command -- sleep 3600
kubectl exec test-net -- wget -qO- http://kubernetes.default.svc.cluster.local

# Test cross-node pod connectivity
# Run a test pod on each node, then curl between them

# Check DNS
kubectl exec test-net -- nslookup kubernetes.default

# Check service routing (no kube-proxy, Cilium handles it)
kubectl get svc -A
# Test a real service like ingress-nginx

# Clean up
kubectl delete pod test-net
```

### Phase 5: Cleanup

#### 5a. Remove flannel artifacts

```bash
# Remove flannel CNI config
ssh backbone01 'rm -f /etc/cni/net.d/10-flannel.conflist /opt/cni/bin/flannel'
ssh frontline01 'rm -f /etc/cni/net.d/10-flannel.conflist /opt/cni/bin/flannel'

# Remove flannel ClusterRole/Binding
kubectl delete clusterrolebinding flannel-crb 2>/dev/null || true
kubectl delete clusterrole flannel 2>/dev/null || true

# Clean up flannel etcd data (optional, after validation)
# etcdctl del /coreos.com/network --prefix
```

#### 5b. Remove old flannel bridge/interfaces

```bash
# On each node:
ip link delete flannel.1 2>/dev/null || true
ip link delete mynet0 2>/dev/null || true  
```

#### 5c. Update VM tests

Update `tests/vm/backbone-control-plane.nix` and `tests/vm/frontline-worker.nix`:
- Remove `systemd.services.flannel` overrides
- Replace `wait_for_unit("flannel.service")` with cilium pod checks
- Or simplify: just check that kube-apiserver is healthy and nodes are Ready

---

## NixOS Module Changes Summary

| File | Action |
|------|--------|
| `modules/profiles/kubernetes/control-plane.nix` | Remove flannel unit, flannel pkg, kube-proxy GODEBUG; add cilium import |
| `modules/profiles/kubernetes/worker.nix` | Remove kube-proxy GODEBUG; add cilium import |
| `modules/profiles/kubernetes/cilium.nix` | **NEW** — disables flannel + kube-proxy, adds kernel modules, firewall rules |
| `lib/helm/charts/cilium.nix` | **NEW** — Cilium Helm values |
| `lib/helm/charts/default.nix` | Add cilium chart |
| `modules/outputs/bootstrap/cilium.nix` | **NEW** — bootstrap manifest |
| `tests/vm/backbone-control-plane.nix` | Update to remove flannel references |
| `tests/vm/frontline-worker.nix` | Update to remove flannel references |

---

## Rollback Plan

If things go wrong:

1. **Immediate rollback** — redeploy the previous NixOS config:
   ```bash
   cd QuadNix && git revert HEAD  # or checkout previous commit
   nix run github:serokell/deploy-rs -- .#backbone-01 --skip-checks
   nix run github:serokell/deploy-rs -- .#frontline-01 --skip-checks
   ```

2. **Restore flannel** — the previous config has the full flannel systemd unit, so reverting the NixOS deploy brings it back.

3. **Remove Cilium**:
   ```bash
   kubectl delete ds cilium -n kube-system
   kubectl delete -f result/cilium.yaml
   ```

4. **Restore etcd snapshot** (if etcd got corrupted):
   ```bash
   # Stop etcd, restore, restart
   ssh backbone01 'systemctl stop etcd'
   ssh backbone01 'ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd/snapshot-pre-cilium.db --data-dir /var/lib/etcd/new'
   ssh backbone01 'rm -rf /var/lib/etcd/data && mv /var/lib/etcd/new /var/lib/etcd/data'
   ssh backbone01 'systemctl start etcd'
   ```

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Pod networking outage during swap | Schedule maintenance window; Cilium DaemonSet boots fast (<30s) |
| kube-proxy removal breaks service routing | Cilium strictly replaces kube-proxy; test immediately after deploy |
| Kernel missing BPF features | Verify kernel version on both nodes before starting |
| CNI config conflict (old flannel + new cilium) | Clean up `/etc/cni/net.d/` on each node; Cilium writes its own config |
| ArgoCD loses connectivity during migration | ArgoCD is on backbone-01; if CNI swap is fast, it self-heals |
| Only 2 nodes — no redundancy | Accept brief downtime; the maintenance window approach minimizes risk |
| Flannel etcd data left behind | Clean up after validation; doesn't interfere with Cilium |

---

## Post-Migration Enhancements (Future)

1. **Enable Hubble** — observability, flow logs, service map UI
2. **Network Policies** — add default-deny policies per namespace
3. **Transparent encryption** — WireGuard-based pod-to-pod encryption
4. **Cluster Mesh** — if you add a second cluster
5. **Cilium metrics** — integrate with existing Prometheus/Grafana monitoring
6. **kube-proxy removal validation** — `cilium status --verbose` should show "KubeProxyReplacement: Strict"

---

## Timeline Estimate

| Phase | Duration |
|-------|----------|
| Phase 1: Prepare Nix configs & Helm chart | 1-2 hours (coding) |
| Phase 2: Module modifications | 30 min (straightforward removals) |
| Phase 3: Build & inspect manifests | 15 min |
| Phase 4: Migration execution | 15-30 min (mostly deploy wait time) |
| Phase 5: Cleanup | 30 min |
| **Total** | **~3-4 hours** |
