# Kubernetes Scheduler Troubleshooting

## Issue: scheduler.extraOpts causing service failure

**Date:** 2026-04-22

### Problem Description

The `kube-scheduler.service` was failing on every boot with the error:

```
Error: unknown flag: --percentage-of-nodes-to-score
```

The configuration in `modules/profiles/kubernetes/control-plane.nix`:

```nix
scheduler.extraOpts = "--percentage-of-nodes-to-score=200";
```

### Root Causes

1. **Invalid flag**: The `--percentage-of-nodes-to-score` flag **does not exist** in Kubernetes 1.35.0. It was removed in K8s 1.27+.

2. **NixOS module not applying option**: The `services.kubernetes.scheduler.extraOpts` option was defined in the config, but the NixOS module system (`/nix/store/4ggd0kb8as38xa0kr730qpnsa89df0x7-source/nixos/modules/services/cluster/kubernetes/scheduler.nix`) wasn't properly passing it to the ExecStart. The module uses `lib.mkIf cfg.enable` but the option wasn't being merged into the final systemd unit.

### Fix Applied

Removed the invalid `scheduler.extraOpts` line from `control-plane.nix`:

```nix
# REMOVED - flag doesn't exist in K8s 1.35.0
# scheduler.extraOpts = "--percentage-of-nodes-to-score=200";
```

### Commands to Check

```bash
# Check scheduler status
ssh backbone01 'sudo systemctl status kube-scheduler'

# Check what options are being passed
ssh backbone01 'sudo cat /etc/systemd/system/kube-scheduler.service | grep ExecStart'

# Check NixOS option value
ssh backbone01 'sudo nixos-option services.kubernetes.scheduler.extraOpts'
```

### Alternative Approaches for CPU Overprovisioning

The `--percentage-of-nodes-to-score` flag was not the right approach. Alternative ways to handle resource overprovisioning:

1. **Pod Priority Classes** - Configure pod priorities with preemption
2. **Resource Limits/Requests** - Tune resource requests to allow more pods per node
3. **PodDisruptionBudgets** - Control pod eviction during disruptions
4. **Cluster Autoscaler** - Let the cluster scale based on demand
5. **VPA (Vertical Pod Autoscaler)** - Automatically adjust pod resource requests

### Related Files

- Config: `modules/profiles/kubernetes/control-plane.nix`
- NixOS module: `nixpkgs/nixos/modules/services/cluster/kubernetes/scheduler.nix`
- Service unit: `/etc/systemd/system/kube-scheduler.service`

### Additional Issue: Git Remote Mismatch

**Problem:** backbone01's `/etc/nixos` Git remote pointed to GitHub instead of Forgejo.

```bash
# Check remote (backbone01)
ssh backbone01 'cd /etc/nixos && git remote -v'
# Output: origin  https://github.com/benjamin-voca/nix (push)

# Should be Forgejo:
# origin  ssh://git@forge-ssh.quadtech.dev/QuadCoreTech/nix.git (push)
```

**Fix:**

```bash
ssh backbone01 'cd /etc/nixos && \
  sudo git remote add forgejo ssh://git@forge-ssh.quadtech.dev/QuadCoreTech/nix.git && \
  sudo git fetch forgejo && \
  sudo git reset --hard forgejo/main'
```

### Lessons Learned

1. Always verify flags exist in the K8s version being used
2. Check where each server pulls from - local and remote "origin" may differ
3. When diagnosing cluster issues, verify the Git state on the actual servers