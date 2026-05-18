# Rook-Ceph bootstrap module
# Rook-Ceph operator + cluster + namespace + RGW user + bucket job + scheduled backups
{
  pkgs,
  lib,
  existingCharts,
}: let
  rookCephChart = existingCharts."rook-ceph";
  rookCephClusterChart = existingCharts."rook-ceph-cluster";

  rookCephNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: rook-ceph
      labels:
        app.kubernetes.io/name: rook-ceph
  '';

  cephRgwCnpgUser = ''
    apiVersion: ceph.rook.io/v1
    kind: CephObjectStoreUser
    metadata:
      name: cnpg-backups
      namespace: rook-ceph
    spec:
      store: ceph-objectstore
      displayName: CNPG Backups
  '';

  cephRgwCnpgBucketJob = ''
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: ceph-rgw-cnpg-backups-bucket
      namespace: rook-ceph
    spec:
      backoffLimit: 6
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: create-bucket
              image: amazon/aws-cli:2.17.40
              env:
                - name: AWS_ACCESS_KEY_ID
                  valueFrom:
                    secretKeyRef:
                      name: rook-ceph-object-user-ceph-objectstore-cnpg-backups
                      key: AccessKey
                - name: AWS_SECRET_ACCESS_KEY
                  valueFrom:
                    secretKeyRef:
                      name: rook-ceph-object-user-ceph-objectstore-cnpg-backups
                      key: SecretKey
                - name: AWS_DEFAULT_REGION
                  value: us-east-1
              command:
                - /bin/sh
                - -ec
                - |
                  ENDPOINT="http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local"
                  if aws --endpoint-url "$ENDPOINT" s3api head-bucket --bucket cnpg-backups >/dev/null 2>&1; then
                    echo "Bucket cnpg-backups already exists"
                    exit 0
                  fi
                  aws --endpoint-url "$ENDPOINT" s3api create-bucket --bucket cnpg-backups
                  echo "Bucket cnpg-backups created"
  '';

  edukursCnpgScheduledBackup = ''
    apiVersion: postgresql.cnpg.io/v1
    kind: ScheduledBackup
    metadata:
      name: edukurs-db-ceph-hourly
      namespace: edukurs
    spec:
      schedule: "0 0 * * * *"
      immediate: true
      backupOwnerReference: cluster
      method: barmanObjectStore
      cluster:
        name: edukurs-db-ceph
  '';

  forgejoCnpgScheduledBackup = ''
    apiVersion: postgresql.cnpg.io/v1
    kind: ScheduledBackup
    metadata:
      name: forgejo-db-hourly
      namespace: forgejo
    spec:
      schedule: "0 15 * * * *"
      immediate: true
      backupOwnerReference: cluster
      method: barmanObjectStore
      cluster:
        name: forgejo-db
  '';
in {
  chartFiles = {
    "02-rook-ceph.yaml" = rookCephChart;
    "03-rook-ceph-cluster.yaml" = rookCephClusterChart;
  };

  inlineFiles = {
    "02d-rook-ceph-namespace.yaml" = rookCephNamespace;
    "02e-ceph-rgw-cnpg-user.yaml" = cephRgwCnpgUser;
    "02f-ceph-rgw-cnpg-bucket-job.yaml" = cephRgwCnpgBucketJob;
    "02g-edukurs-cnpg-scheduled-backup.yaml" = edukursCnpgScheduledBackup;
    "02h-forgejo-cnpg-scheduled-backup.yaml" = forgejoCnpgScheduledBackup;
  };

  # Rook-Ceph operator chart needs annotation stripping
  needsAnnotationStrip = ["02-rook-ceph.yaml"];

  # Rook-Ceph cluster chart needs StorageClass filtering
  needsStorageClassFilter = ["03-rook-ceph-cluster.yaml"];

  order = [
    "02d-rook-ceph-namespace.yaml"
    "02-rook-ceph.yaml"
    "03-rook-ceph-cluster.yaml"
    "02e-ceph-rgw-cnpg-user.yaml"
    "02f-ceph-rgw-cnpg-bucket-job.yaml"
    "02g-edukurs-cnpg-scheduled-backup.yaml"
    "02h-forgejo-cnpg-scheduled-backup.yaml"
  ];
}
