# CNPG bootstrap module
# CloudNativePG operator + cluster + namespace + databases
{
  pkgs,
  lib,
  existingCharts,
}: let
  cnpgOperatorChart = existingCharts.cloudnative-pg;

  cnpgNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: cnpg-system
      labels:
        app.kubernetes.io/name: cloudnative-pg
  '';

  cnpgCluster = ''
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: shared-pg
      namespace: cnpg-system
    spec:
      instances: 1
      storage:
        storageClass: ceph-block
        size: 10Gi
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
      bootstrap:
        initdb:
          database: edukurs
          owner: edukurs
          secret:
            name: shared-pg-app
      postgresql:
        pg_hba:
          - host all all 0.0.0.0/0 md5
          - host all all ::0/0 md5
      backup:
        barmanObjectStore:
          destinationPath: "s3://cnpg-backups/"
          endpointURL: "http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local"
          s3Credentials:
            accessKeyId:
              name: ceph-rgw-s3-credentials
              key: ACCESS_KEY_ID
            secretAccessKey:
              name: ceph-rgw-s3-credentials
              key: ACCESS_SECRET_KEY
            region:
              name: ceph-rgw-s3-credentials
              key: ACCESS_REGION
    ---
    apiVersion: v1
    kind: Secret
    metadata:
      name: shared-pg-app
      namespace: cnpg-system
    type: Opaque
    stringData:
      username: edukurs
      password: PLACEHOLDER
      dbname: edukurs
    ---
    apiVersion: postgresql.cnpg.io/v1
    kind: Database
    metadata:
      name: batllavatourist
      namespace: cnpg-system
    spec:
      cluster:
        name: shared-pg
      owner: app
    ---
    apiVersion: postgresql.cnpg.io/v1
    kind: Database
    metadata:
      name: quadpacienti
      namespace: cnpg-system
    spec:
      cluster:
        name: shared-pg
      owner: app
    ---
    apiVersion: postgresql.cnpg.io/v1
    kind: Database
    metadata:
      name: grafana
      namespace: cnpg-system
    spec:
      cluster:
        name: shared-pg
      name: grafana
      owner: edukurs
  '';
in {
  chartFiles = {
    "02a-cnpg-operator.yaml" = cnpgOperatorChart;
  };

  inlineFiles = {
    "02c-cnpg-namespace.yaml" = cnpgNamespace;
    "02b-cnpg-cluster.yaml" = cnpgCluster;
  };

  # CNPG operator chart needs annotation stripping
  needsAnnotationStrip = ["02a-cnpg-operator.yaml"];

  order = ["02a-cnpg-operator.yaml" "02b-cnpg-cluster.yaml" "02c-cnpg-namespace.yaml"];
}
