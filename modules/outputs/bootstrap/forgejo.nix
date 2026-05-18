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

  forgejoDbStorageclassPatch = ''
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: forgejo-db
      namespace: forgejo
    spec:
      storage:
        storageClass: ceph-block
        size: 20Gi
      instances: 3
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
    "04-forgejo-actions.yaml"
  ];
}
