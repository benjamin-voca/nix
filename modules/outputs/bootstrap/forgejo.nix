# Forgejo bootstrap module
# Forgejo chart + namespace + PVC + DB storageclass + runner secret + actions + scheduled backup namespace
{
  pkgs,
  lib,
  existingCharts,
}: let
  forgejoChart = existingCharts.forgejo;
  forgejoActionsChart = existingCharts."forgejo-actions";

  forgejoNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: forgejo
      labels:
        app.kubernetes.io/name: forgejo
  '';

  forgejoSharedStoragePvc = ''
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: forgejo-shared-storage-ceph-csi
      namespace: forgejo
    spec:
      accessModes:
        - ReadWriteMany
      storageClassName: ceph-filesystem-csi
      resources:
        requests:
          storage: 50Gi
  '';

  # NOTE: despite the "patch" name this is the full forgejo-db Cluster spec
  # (applied via `kubectl apply`). It defines the CNPG postgres cluster used
  # by Forgejo, so storage sizing and postgres tuning live here.
  forgejoDbStorageclassPatch = ''
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: forgejo-db
      namespace: forgejo
    spec:
      # Single instance — replicas on one node give no availability benefit
      instances: 1
      storage:
        storageClass: ceph-block
        size: 40Gi
      postgresql:
        parameters:
          # Cap how much WAL a single replication slot may retain. The
          # default (-1 = unlimited) let a diverged replica's slot pin WAL
          # until pg_wal filled the entire 20Gi data volume and prevented
          # the primary from starting (Forgejo SSH then failed with
          # "Key check failed" because the DB was unreachable). 2GB is
          # generous for a healthy replica to catch up while guaranteeing
          # a stuck slot can never exhaust the disk again.
          max_slot_wal_keep_size: 2GB
  '';

  forgejoRunnerSecret = ''
    apiVersion: v1
    kind: Secret
    metadata:
      name: forgejo-runner-token
      namespace: forgejo
    type: Opaque
    stringData:
      token: RUNNER_TOKEN_PLACEHOLDER
  '';

  # Mounted into the dind sidecar of the forgejo-actions statefulset so
  # the Docker daemon trusts 10.0.0.56:5000 (HTTP, no TLS) and can pull
  # images through Harbor's pull-through cache. Without
  # `insecure-registries`, `docker pull 10.0.0.56:5000/...` fails with
  # "server gave HTTP response to HTTPS client".
  forgejoRunnerDaemonConfig = ''
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: forgejo-runner-daemon-config
      namespace: forgejo
      labels:
        app.kubernetes.io/name: forgejo-runner-daemon-config
    data:
      daemon.json: |
        {
          "insecure-registries": ["10.0.0.56:5000"]
        }
  '';
in {
  chartFiles = {
    "03-forgejo.yaml" = forgejoChart;
    "04-forgejo-actions.yaml" = forgejoActionsChart;
  };

  inlineFiles = {
    "02i-forgejo-namespace.yaml" = forgejoNamespace;
    "03a-forgejo-shared-storage-ceph-pvc.yaml" = forgejoSharedStoragePvc;
    "03b-forgejo-db-storageclass-patch.yaml" = forgejoDbStorageclassPatch;
    "04-forgejo-runner-secret.yaml" = forgejoRunnerSecret;
    "04a-forgejo-runner-daemon-config.yaml" = forgejoRunnerDaemonConfig;
  };

  # Forgejo chart needs service targetPort normalization
  needsForgejoPortFix = true;

  # Forgejo-actions chart needs serviceName injection and conditional inclusion
  needsForgejoActionsFix = true;

  order = [
    "02i-forgejo-namespace.yaml"
    "03-forgejo.yaml"
    "03a-forgejo-shared-storage-ceph-pvc.yaml"
    "03b-forgejo-db-storageclass-patch.yaml"
    "04-forgejo-runner-secret.yaml"
    "04a-forgejo-runner-daemon-config.yaml"
    "04-forgejo-actions.yaml"
  ];
}
