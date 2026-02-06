# Kubernetes Architecture

## Current State (Now)

- Only `backbone-01` exists.
- `backbone-01` must run **both** the control plane and worker roles.
- All cluster services (ArgoCD, Gitea, ClickHouse, etc.) are intended to run on backbone nodes.

## Target Topology (Future)

### Backbone Nodes
- Purpose: control plane + core services.
- Will run:
  - Kubernetes control plane components.
  - Cluster services defined in this repo (ArgoCD, Gitea, ClickHouse, etc.).

### Frontline Nodes
- Purpose: pure worker nodes for workloads.
- No control plane services.
- No cluster management services.

## Control Plane Strategy Options

### Option A: HA Control Plane Across Backbones

**Pros**
- Survives any single backbone failure.
- No single-point-of-failure.
- Scales with the backbone fleet.

**Cons**
- More complex to bootstrap.
- Requires stable inter-backbone networking and etcd quorum.

**Recommended when**
- You have 3+ backbone nodes.
- Backbone nodes are stable and always powered.

### Option B: Dedicated Control Plane Laptop

**Pros**
- Battery-backed for power failures.
- Simpler initial setup.
- Predictable control-plane host.

**Cons**
- Single point of failure if the laptop is offline.
- Less scalable, requires careful backup/restore of etcd.

**Recommended when**
- You only have 1-2 backbone nodes right now.
- You want reliable power for control plane.

## Current Implementation (NixOS Built-in Kubernetes)

### Control Plane + Worker on backbone-01
- Use NixOS built-in Kubernetes module.
- `modules/profiles/kubernetes/control-plane.nix` enables:
  - `services.kubernetes.roles = [ "master" "node" ]`
  - `virtualisation.containerd.enable = true`
- `modules/profiles/kubernetes/allow-master-workloads.nix` disables the control-plane taint

### Future Worker Nodes
- Use `modules/profiles/kubernetes/worker.nix`.
- Set `services.kubernetes.masterAddress` to the control plane host.

## Cluster Services Placement

- All cluster services should be deployed on backbone nodes.
- Frontline nodes should be reserved for workload pods only.

## Next Steps

1) Keep `backbone-01` as control plane + worker for now.
2) When backbone-02/03 exist, decide between HA control plane vs dedicated laptop.
3) Update `modules/hosts/*` and `modules/roles/*` accordingly.
