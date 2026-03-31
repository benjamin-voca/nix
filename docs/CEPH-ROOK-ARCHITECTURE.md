# Rook + Ceph Architecture (QuadNix)

This document describes the storage architecture used by QuadNix.

## Goals

- Block storage via Ceph RBD (`ceph-block`).
- Object storage via Ceph RGW for CNPG backups.
- Keep ERPNext RWX data on `nfs-rwx-v2`.
- Keep everything declarative in this repo.

## Control Plane Layout

- **Rook operator chart**: `lib/helm/charts/rook-ceph.nix`
- **Rook cluster chart**: `lib/helm/charts/rook-ceph-cluster.nix`
- **Chart sources/pins**:
  - `charts/rook-release/rook-ceph/default.nix`
  - `charts/rook-release/rook-ceph-cluster/default.nix`
- **Bootstrap wiring**: `modules/outputs/bootstrap.nix`

## Storage Endpoints

- **Block**: StorageClass `ceph-block` (default target for most PVCs)
- **Object**: RGW service `rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local`
- **Bucket claims**: StorageClass `ceph-bucket`

## Current Single-Node Design

`backbone-01` has one 1TB HDD (`/dev/sda`) used directly by Ceph OSDs.

- Defined in `lib/helm/charts/rook-ceph-cluster.nix` under `cephClusterSpec.storage.nodes`
- Node `backbone-01` device `/dev/sda`

## Extending Capacity

- Add more backbone nodes and additional OSDs first.
- Then increase replication and failure domains.
- For production durability, avoid running replicated data with a single OSD/node.
