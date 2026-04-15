# CNPG Disaster Recovery Playbook

> How to restore a CloudNativePG (CNPG/PostgreSQL) cluster from Rook-Ceph S3 backups.
> General guide — replace the placeholders with your actual cluster/credential values.

---

## Overview

| Component | Detail |
|---|---|
| **Backup Target** | `s3://cnpg-backups/<cluster-name>/` on Rook-Ceph RGW |
| **Backup Method** | CNPG `ScheduledBackup` — hourly Barman-style base backups + WAL archiving |
| **Restore Strategy** | `pg_basebackup` style (data.tar + WAL replay) |
| **PG Version** | PostgreSQL 18 (system) |

---

## Prerequisites

```bash
# kubectl context pointing to your cluster
kubectl config current-context

# Ceph RGW port-forward (keep running in a separate terminal)
kubectl port-forward -n rook-ceph svc/rook-ceph-rgw-ceph-objectstore 7480:80 &
sleep 3
curl http://localhost:7480  # should return XML bucket listing
```

### Ceph S3 Credentials

```bash
# Get from the cluster secret (replace names with yours)
ACCESS_KEY=$(kubectl get secret <s3-secret-name> -n <namespace> \
  -o jsonpath='{.data.ACCESS_KEY_ID}' | base64 -d)
SECRET_KEY=$(kubectl get secret <s3-secret-name> -n <namespace> \
  -o jsonpath='{.data.ACCESS_SECRET_KEY}' | base64 -d)

export AWS_ACCESS_KEY_ID=$ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:7480
```

---

## Finding the Right Backup

### List all base backups (most recent first)

```bash
aws s3 ls s3://cnpg-backups/<cluster-name>/<cluster-name>/base/ \
  --endpoint-url http://localhost:7480 | sort | tail -10
```

Example output:
```
2026-04-15 01:00:05       1433 edukurs-db-ceph/edukurs-db-ceph/base/20260415T010000/backup.info
2026-04-15 01:00:05   35502080 edukurs-db-ceph/edukurs-db-ceph/base/20260415T010000/data.tar
```

Each backup has:
- `data.tar` — the pg_basebackup snapshot
- `backup.info` — metadata (LSN, timeline, WAL segment references)
- Associated WAL segments in `wals/`

### Check backup metadata

```bash
LATEST=$(aws s3 ls s3://cnpg-backups/<cluster-name>/<cluster-name>/base/ \
  --endpoint-url http://localhost:7480 | sort | tail -1 | awk '{print $2}' | tr -d '/')

aws s3 cp "s3://cnpg-backups/<cluster-name>/<cluster-name>/base/${LATEST}backup.info" - \
  --endpoint-url http://localhost:7480
```

Look for `start-lsn` and `end-lsn` — you'll need these for WAL replay.

---

## Restore to Local Docker (for testing)

Spins up a PostgreSQL container with the restored data. Use this to verify a backup
before touching prod.

### Step 1 — Download the backup

```bash
LATEST="20260415T010000"   # <-- replace with your target backup timestamp

mkdir -p /tmp/pg-restore/18/main
aws s3 cp \
  "s3://cnpg-backups/<cluster-name>/<cluster-name>/base/${LATEST}/data.tar" \
  /tmp/pg-restore/18/main/data.tar \
  --endpoint-url http://localhost:7480

tar -xf /tmp/pg-restore/18/main/data.tar \
  -C /tmp/pg-restore/18/main
```

### Step 2 — Sanitize CNPG config files

CNPG injects runtime config into the data directory. These must be cleared
before a plain PostgreSQL container can start:

```bash
> /tmp/pg-restore/18/main/override.conf
> /tmp/pg-restore/18/main/custom.conf
> /tmp/pg-restore/18/main/postgresql.auto.conf

cat > /tmp/pg-restore/18/main/pg_hba.conf << 'EOF'
local   all             all                                     trust
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::0/0                   scram-sha-256
EOF
```

### Step 3 — Fetch WAL segment for recovery

CNPG backups are taken with `pg_basebackup --wal-method=stream`. The `data.tar`
contains everything up to the base backup's LSN. If the container fails to start
due to an incomplete checkpoint, fetch the WAL:

```bash
# From backup.info: end-WAL-file = 000000010000000200000068  (example — check yours)

aws s3 cp \
  "s3://cnpg-backups/<cluster-name>/<cluster-name>/wals/0000000100000002/000000010000000200000068" \
  /tmp/pg-restore/18/main/pg_wal/000000010000000200000068 \
  --endpoint-url http://localhost:7480

# Signal PostgreSQL to recover from archive
touch /tmp/pg-restore/18/main/recovery.signal

# Configure restore command
cat > /tmp/pg-restore/18/main/postgresql.auto.conf << 'EOF'
restore_command = 'cp /var/lib/postgresql/18/main/pg_wal/%f %p'
recovery_target_timeline = 'latest'
recovery_target_action = 'promote'
max_worker_processes = 32
max_parallel_workers = 32
max_replication_slots = 32
wal_level = logical
listen_addresses = '*'
EOF
```

### Step 4 — Start the container

```bash
docker run -d \
  --name pg-restore-test \
  -e POSTGRES_USER=<user> \
  -e POSTGRES_PASSWORD=<password> \
  -e POSTGRES_DB=<database> \
  -e PGDATA=/var/lib/postgresql/18/main \
  -p 5432:5432 \
  -v /tmp/pg-restore:/var/lib/postgresql \
  postgres:18-alpine
```

Wait for startup:
```bash
sleep 5
docker logs pg-restore-test | grep "database system is ready"

# Connect
psql -h localhost -p 5432 -U <user> -d <database>
```

### Expected successful recovery logs

```
LOG:  restored log file "000000010000000200000068" from archive
LOG:  redo done at 2/68000120 system usage: CPU: user: 0.00 s
LOG:  selected new timeline ID: 2
LOG:  archive recovery complete
LOG:  database system is ready to accept connections
```

---

## Full Prod Cluster Restore (Catastrophic Loss)

> ⚠️ **WARNING**: This destroys the existing CNPG cluster. Only do this if the cluster is
> completely unrecoverable. If the cluster is still running, prefer in-place recovery.

### Step 1 — Capture a final backup of whatever remains

```bash
# Trigger a CNPG backup manually (creates a new base backup now)
kubectl annotate backup scheduledbackup.<cluster-name>-hourly \
  cnpg.io/scheduled-backup=true -n <namespace> --overwrite

# Wait for it to complete
kubectl wait --for=condition=Completed backup \
  -n <namespace> --all --timeout=300s 2>/dev/null || true
```

### Step 2 — Delete the existing cluster

```bash
kubectl delete cluster <cluster-name> -n <namespace>
# Wait for all pods to terminate
kubectl wait --for=delete pods -n <namespace> \
  -l "cnpg.io/cluster=<cluster-name>" --timeout=120s
```

### Step 3 — Recreate the cluster from backup

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <cluster-name>
  namespace: <namespace>
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie
  bootstrap:
    recovery:
      backup:
        name: <backup-timestamp>   # e.g. 20260415T010000
  backup:
    barmanObjectStore:
      destinationPath: s3://cnpg-backups/<cluster-name>
      endpointURL: http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local
      s3Credentials:
        accessKeyId:
          key: ACCESS_KEY_ID
          name: <s3-secret-name>
        secretAccessKey:
          key: ACCESS_SECRET_KEY
          name: <s3-secret-name>
        region:
          key: ACCESS_REGION
          name: <s3-secret-name>
  storage:
    size: 10Gi
    storageClass: ceph-block
```

```bash
kubectl apply -f - << 'EOF'
# (paste the YAML above with your values)
EOF

# Watch the bootstrap
kubectl logs -n <namespace> -l "cnpg.io/cluster=<cluster-name>" -f
```

The new primary automatically pulls the backup from S3 and recovers.

---

## WAL Archive Access

WAL segments are stored at:
```
s3://cnpg-backups/<cluster-name>/<cluster-name>/wals/0000000100000002/
```

Segment naming: `0000000100000002XXXXXXXX` (8-digit hex WAL segment number).

### List WALs in a time window

```bash
aws s3 ls "s3://cnpg-backups/<cluster-name>/<cluster-name>/wals/0000000100000002/" \
  --endpoint-url http://localhost:7480 | grep "2026-04-15 02:"
```

### Point-in-time recovery

Download the WAL range between your backup and target time:

```bash
for SEG in $(seq 0x60 0x70); do
  SEG_HEX=$(printf "%08x" $SEG)
  aws s3 cp \
    "s3://cnpg-backups/<cluster-name>/<cluster-name>/wals/0000000100000002/0000000100000002000000${SEG_HEX}" \
    /tmp/pg-restore/18/main/pg_wal/ \
    --endpoint-url http://localhost:7480
done
```

Add PITR target to `postgresql.auto.conf`:
```
recovery_target_time = '2026-04-15 03:00:00+00'
recovery_target_action = 'pause'
```

---

## Troubleshooting

### "FATAL: must specify restore_command when standby mode is not enabled"

The `data.tar` was taken with `pg_basebackup` (not streaming replication), so PostgreSQL
expects WAL replay. Add `recovery.signal` and a `restore_command` in `postgresql.auto.conf`
(see Step 3 above).

### "FATAL: could not locate required checkpoint record"

The WAL segment is missing from pg_wal. Download the correct WAL segment (check
`backup.info`'s `end-WAL-file` field) from S3.

### "FATAL: recovery aborted because of insufficient parameter settings"

PostgreSQL 18 validates that certain settings match between the backup and target.
Set `max_worker_processes = 32` (or matching value) in `postgresql.auto.conf`.

### CNPG pod stuck in `ContainerCreating`

The PVC may be stuck. Check:
```bash
kubectl describe pvc -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -10
```

### Ceph RGW unreachable

Check the Rook operator and Ceph health:
```bash
kubectl get pods -n rook-ceph
kubectl exec -n rook-ceph deploy/rook-ceph-operator -- \
  rook ceph health
```

### "column is in a primary key" — `db:push` fails after restore

If you're restoring EduKurs or a DB with Drizzle-named NOT NULL constraints:
PG 18 refuses to drop named NOT NULL constraints on primary key columns. The cleanup
SQL and Dockerfile `sed` patch in that project's docs handle this.