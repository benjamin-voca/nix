# Mosaic namespace + CI RBAC + Ceph RGW user + bucket job
{
  pkgs,
  lib,
}: let
  mosaicNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: mosaic
      labels:
        app.kubernetes.io/name: mosaic
  '';

  mosaicCiRbac = ''
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: gitea-ci
      namespace: mosaic
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: Role
    metadata:
      name: mosaic-ci-deployer
      namespace: mosaic
    rules:
      - apiGroups: ["apps"]
        resources: ["deployments"]
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
      - apiGroups: ["batch"]
        resources: ["jobs", "cronjobs"]
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
      - apiGroups: [""]
        resources: ["services", "configmaps", "secrets", "pods"]
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
      - apiGroups: ["networking.k8s.io"]
        resources: ["ingresses"]
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
      - apiGroups: ["postgresql.cnpg.io"]
        resources: ["clusters", "databases"]
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
      - apiGroups: [""]
        resources: ["persistentvolumeclaims"]
        verbs: ["get", "list", "watch"]
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: gitea-ci-deployer
      namespace: mosaic
    subjects:
      - kind: ServiceAccount
        name: gitea-ci
        namespace: mosaic
    roleRef:
      kind: Role
      name: mosaic-ci-deployer
      apiGroup: rbac.authorization.k8s.io
    ---
    apiVersion: v1
    kind: Secret
    metadata:
      name: gitea-ci-token
      namespace: mosaic
      annotations:
        kubernetes.io/service-account.name: gitea-ci
    type: kubernetes.io/service-account-token
  '';

  mosaicRgwUser = ''
    apiVersion: ceph.rook.io/v1
    kind: CephObjectStoreUser
    metadata:
      name: mosaic
      namespace: rook-ceph
    spec:
      store: ceph-objectstore
      displayName: Mosaic
  '';

  mosaicRgwBucketJob = ''
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: ceph-rgw-mosaic-buckets
      namespace: rook-ceph
    spec:
      backoffLimit: 6
      ttlSecondsAfterFinished: 86400
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: create-buckets
              image: amazon/aws-cli:2.17.40
              env:
                - name: AWS_ACCESS_KEY_ID
                  valueFrom:
                    secretKeyRef:
                      name: rook-ceph-object-user-ceph-objectstore-mosaic
                      key: AccessKey
                - name: AWS_SECRET_ACCESS_KEY
                  valueFrom:
                    secretKeyRef:
                      name: rook-ceph-object-user-ceph-objectstore-mosaic
                      key: SecretKey
                - name: AWS_DEFAULT_REGION
                  value: us-east-1
              command:
                - /bin/sh
                - -ec
                - |
                  ENDPOINT="http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local"
                  for b in catalog-assets catalog-imports catalog-renders catalog-promo mosaic-preview; do
                    if aws --endpoint-url "$ENDPOINT" s3api head-bucket --bucket "$b" >/dev/null 2>&1; then
                      echo "Bucket $b already exists"
                    else
                      aws --endpoint-url "$ENDPOINT" s3api create-bucket --bucket "$b"
                      echo "Bucket $b created"
                    fi
                  done
  '';
in {
  chartFiles = {};

  inlineFiles = {
    "21-mosaic-namespace.yaml" = mosaicNamespace;
    "21a-mosaic-ci-rbac.yaml" = mosaicCiRbac;
    "21b-mosaic-rgw-user.yaml" = mosaicRgwUser;
    "21c-mosaic-rgw-buckets.yaml" = mosaicRgwBucketJob;
  };

  order = [
    "21-mosaic-namespace.yaml"
    "21a-mosaic-ci-rbac.yaml"
    "21b-mosaic-rgw-user.yaml"
    "21c-mosaic-rgw-buckets.yaml"
  ];
}
