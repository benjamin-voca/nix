# Rook + Ceph Operations Runbook

This runbook focuses on operations for the QuadNix Rook/Ceph stack.

## Quick Health Checks

```sh
kubectl -n rook-ceph get pods
kubectl -n rook-ceph get cephcluster,cephblockpool,cephobjectstore
kubectl get sc
```

If toolbox is enabled:

```sh
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- rados df
```

## Known NixOS-Specific Pitfalls

### 1) Kubelet root dir mismatch

Rook CSI must use the actual kubelet root dir. In this cluster it is `/var/lib/kubernetes`.

- Configured in: `lib/helm/charts/rook-ceph.nix`
- Key: `csi.kubeletDirPath = "/var/lib/kubernetes"`

Symptoms if wrong:

- ceph-csi nodeplugin mount errors
- hostPath mount failures for kubelet plugin dirs

### 2) rbd kernel module path mismatch

On NixOS, CSI pods may not find modules in default paths. This repo maps CSI plugin module volumes to `/run/booted-system/kernel-modules/lib/modules`.

- Configured in: `lib/helm/charts/rook-ceph.nix`

Symptoms if wrong:

- `modprobe rbd` failure in nodeplugin logs
- RBD volume publish/mount failures

### 3) Node name mismatch for CephCluster

If specific nodes are listed in CephCluster storage config, names must match Kubernetes node names exactly.

Symptoms if wrong:

- operator reports no valid storage nodes
- no OSD prepare jobs created

## Migration-Phase Notes

- Temporary OSD-on-PVC is enabled from Longhorn in `lib/helm/charts/rook-ceph-cluster.nix`.
- This is only for bootstrap while Longhorn still owns the raw HDD mount.
- After app/PVC migration, move OSDs to raw devices and remove Longhorn dependencies.

## Useful Debug Commands

```sh
kubectl -n rook-ceph logs deploy/rook-ceph-operator
kubectl -n rook-ceph get jobs
kubectl -n rook-ceph get pvc
kubectl -n rook-ceph describe cephcluster rook-ceph
kubectl -n rook-ceph describe cephblockpool ceph-block-hdd
kubectl -n rook-ceph describe cephobjectstore ceph-objectstore
```

## Post-Change Verification

After any storage config change:

1. Rook operator running and stable.
2. At least one OSD up/in.
3. `ceph-block-hdd` ready.
4. `ceph-objectstore` ready.
5. `ceph-block` StorageClass present and set as intended.
