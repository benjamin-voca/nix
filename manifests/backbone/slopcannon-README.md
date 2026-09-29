# slopcannon on the backbone cluster

DEPLOYED via kaniko → `ctr` import (Harbor push path is broken on this node,
see "Cluster quirks"). Plain YAML mirrored into
`~/Personal/nix/manifests/backbone/` as the declarative record.

## Components

| File | What | Live state |
|---|---|---|
| `slopcannon-cnpg.yaml` | CNPG `Cluster` (5Gi ceph-block) | Manifest kept, object DELETED — the node currently kills non-root socket() (below). DB lives on `shared-pg` instead. |
| `slopcannon-data.yaml` | ObjectBucketClaim `slopcannon-clips` (Rook RGW, `ceph-bucket` SC) + redis Deployment | OBC Bound (bucket `slopcannon-clips-c6090ad9…`, creds in secret `slopcannon-clips`); redis Running |
| `web.yaml` | ConfigMap + Deployment + NodePort 30080 | Running, image node-local (`imagePullPolicy: Never`) |
| `worker.yaml` | Render worker, replicas 1, `RENDER_CONCURRENCY=1` | image node-local |

- **Database**: `postgres://app:***@shared-pg-rw.cnpg-system.svc:5432/slopcannon`
  (role + database provisioned by hand on the pre-existing `shared-pg` CNPG
  cluster; creds in secret `slopcannon-db-credentials`). Re-provision
  `slopcannon-db` when the node bug is fixed and migrate.
- **Registry**: images are tagged `10.0.0.56:5000/library/<name>:<tag>` but
  imported straight into the node's containerd store, so kubelet needs
  `imagePullPolicy: Never`.

## Build (in-cluster, kaniko → ctr import)

```sh
./infra/k8s/kaniko-build.sh web 0.1.0
./infra/k8s/kaniko-build.sh render-worker 0.1.0   # compiles whisper.cpp, ~15min
```

The job clones from Forgejo (sops token), builds with kaniko `--no-push
--tar-path`, then a privileged `ctr-import` step imports the tar via
`/run/current-system/sw/bin/ctr` (nix-store bin is mounted read-only).
Rerun any time; import overwrites the tag.

## Deploy

```sh
kubectl apply -f infra/k8s/slopcannon-data.yaml
kubectl apply -f infra/k8s/web.yaml -f infra/k8s/worker.yaml
```

Smoke (verified live 2026-09-29):

```sh
curl http://192.168.1.7:30080/api/healthz            # ok
# RPC round-trip + Postgres persistence proven:
# POST /api/rpc/stories/createOriginal → story, sfw approved
# psql on shared-pg-1: SELECT title FROM stories → row present
```

## Cluster quirks (fix belongs in ~/Personal/nix)

1. **Non-root `socket()` EPERM on backbone-01** (kernel 6.18): any process
   calling `socket()` as a non-root UID inside a pod fails with
   `operation not permitted` (reproduced with a bare python pod). This broke
   Harbor's registry and the CNPG operator. Fixes applied live:
   - `cloudnative-pg` Deployment: container/pod `runAsUser: 0`,
     `runAsNonRoot: false`; namespace `cnpg-system` PSA `enforce=baseline`.
   - Harbor `harbor-registry`: still broken (its image overlay denies root
     exec of the entrypoint — noexec-looking). Not fixed; images bypass it.
2. **Harbor registry CrashLoop**: blocked by (1) + entrypoint exec denial.
   When (1) is fixed in nixos, re-point `imagePullPolicy` to `IfNotPresent`
   and switch the kaniko job back to `--destination` push.

Secrets to SOPS-record when convenient: `slopcannon-db-credentials`
(generated at deploy time; already applied to the cluster).
