# Huly — open-source project management platform (hcengineering/huly-selfhost)
# Namespace + Ceph RGW user/bucket + vendored helm chart (huly.voltrum.co)
#
# The upstream chart (huly-selfhost/helm/huly) is vendored at
# lib/helm/charts/vendored/huly and rendered with `helm template` at build
# time. Post-processing in the render derivation:
#   - strips the chart-managed `huly-secret` (created at runtime instead,
#     by k8s-secrets-inject from sops huly-* keys + rook RGW user keys —
#     must exist before apply: cockroach bootstraps its user from
#     COCKROACH_PASSWORD on first boot)
#   - injects metadata.namespace (templates omit it, like clickstack's)
#
# Infra choices (no MinIO, no MongoDB):
#   - file storage: Ceph RGW via the S3 driver, dedicated `huly`
#     object-store user + `huly-data` bucket (STORAGE_CONFIG injected at
#     runtime)
#   - MongoDB: only required by the AI bot, which is disabled
#   - cockroach (metadata), redpanda (queue), elastic (fulltext) come from
#     the chart on ceph-block PVCs
{
  lib,
  pkgs,
  existingCharts,
}: let
  d = import ../../../lib/domain.nix;
  tolerations = "      tolerations:\n        - key: role\n          operator: Equal\n          value: backbone\n          effect: NoSchedule\n        - key: infra\n          operator: Equal\n          value: \"true\"\n          effect: NoSchedule";

  namespace = ''
apiVersion: v1
kind: Namespace
metadata:
  name: huly
  labels:
    app.kubernetes.io/name: huly
'';

  # Dedicated Ceph RGW (S3) user for Huly's file storage.
  # Rook generates AccessKey/SecretKey in
  # rook-ceph/rook-ceph-object-user-ceph-objectstore-huly.
  rgwUser = ''
apiVersion: ceph.rook.io/v1
kind: CephObjectStoreUser
metadata:
  name: huly
  namespace: rook-ceph
spec:
  store: ceph-objectstore
  displayName: Huly
'';

  rgwBucketJob = ''
apiVersion: batch/v1
kind: Job
metadata:
  name: ceph-rgw-huly-buckets
  namespace: rook-ceph
spec:
  backoffLimit: 6
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: OnFailure
${tolerations}
      containers:
        - name: create-buckets
          image: amazon/aws-cli:2.17.40
          env:
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-object-user-ceph-objectstore-huly
                  key: AccessKey
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-object-user-ceph-objectstore-huly
                  key: SecretKey
            - name: AWS_DEFAULT_REGION
              value: us-east-1
          command:
            - /bin/sh
            - -ec
            - |
              ENDPOINT="http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local"
              if aws --endpoint-url "$ENDPOINT" s3api head-bucket --bucket huly-data >/dev/null 2>&1; then
                echo "Bucket huly-data already exists"
              else
                aws --endpoint-url "$ENDPOINT" s3api create-bucket --bucket huly-data
                echo "Bucket huly-data created"
              fi
'';

  # One-shot bootstrap: cockroach start-single-node does NOT auto-create
  # COCKROACH_USER from env, so create it idempotently (password from
  # huly-secret) before the app services connect. Completed job persists;
  # the user lives in the cockroach data volume thereafter.
  cockroachInitJob = ''
apiVersion: batch/v1
kind: Job
metadata:
  name: huly-cockroach-init
  namespace: huly
spec:
  backoffLimit: 12
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: OnFailure
${tolerations}
      containers:
        - name: init-user
          image: cockroachdb/cockroach:latest-v24.2
          env:
            - name: CRDB_USER
              value: selfhost
            - name: CRDB_DB
              value: defaultdb
            - name: CRDB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: huly-secret
                  key: COCKROACH_PASSWORD
          command:
            - /bin/sh
            - -ec
            - |
              until /cockroach/cockroach sql --insecure -u root --host=cockroach -e "SELECT 1" >/dev/null 2>&1; do
                echo "waiting for cockroach..."; sleep 3;
              done
              /cockroach/cockroach sql --insecure -u root --host=cockroach -e "CREATE USER IF NOT EXISTS $CRDB_USER" || true
              # Insecure mode rejects password auth entirely (trust auth); keep
              # the statement for a future secure-mode migration.
              /cockroach/cockroach sql --insecure -u root --host=cockroach -e "ALTER USER $CRDB_USER WITH PASSWORD '$CRDB_PASSWORD'" || true
              /cockroach/cockroach sql --insecure -u root --host=cockroach -e "ALTER DATABASE $CRDB_DB OWNER TO $CRDB_USER" || true
              /cockroach/cockroach sql --insecure -u root --host=cockroach -e "GRANT ALL ON DATABASE $CRDB_DB TO $CRDB_USER" || true
              /cockroach/cockroach sql --insecure -u root --host=cockroach -e "GRANT ALL ON SCHEMA $CRDB_DB.public TO $CRDB_USER" || true
              echo "cockroach user $CRDB_USER ready"
'';

  # ── Chart render ─────────────────────────────────────────────────────────
  # Values are deterministic sentinels where secrets are concerned; the
  # rendered huly-secret Secret is stripped here and created at runtime by
  # k8s-secrets-inject (see module header + k8s-secrets-inject.nix).
  values = {
    domain = d.host "huly";
    hulyVersion = "v0.7.426";

    # Public URL scheme override (vendored configmap.yaml patch): browsers
    # get https at the Cloudflare edge while the tunnel origin hop uses the
    # nginx default cert (chart TLS/cert-manager disabled).
    publicProtocol = "https";
    publicWsProtocol = "wss";

    ingress = {
      enabled = true;
      className = "nginx";
      tls.enabled = false;
      annotations = {
        "nginx.ingress.kubernetes.io/proxy-body-size" = "50m";
      };
    };

    secrets = {
      serverSecret = "INJECTED-AT-RUNTIME";
      cockroachPassword = "INJECTED-AT-RUNTIME";
      redpandaPassword = "INJECTED-AT-RUNTIME";
      aibotPassword = "INJECTED-AT-RUNTIME";
      storageConfig = "INJECTED-AT-RUNTIME";
    };

    storage.type = "s3";
    storage.s3 = {
      endpoint = "http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local";
      region = "us-east-1";
      rootBucket = "huly-data";
      accessKey = "INJECTED-AT-RUNTIME";
      secretKey = "INJECTED-AT-RUNTIME";
    };

    global.tolerations = [
      {
        key = "role";
        operator = "Equal";
        value = "backbone";
        effect = "NoSchedule";
      }
      {
        key = "infra";
        operator = "Equal";
        value = "true";
        effect = "NoSchedule";
      }
    ];

    cockroach = {
      enabled = true;
      storage = "10Gi";
      storageClassName = "ceph-block";
      resources.limits.memory = "1Gi";
    };
    redpanda = {
      enabled = true;
      storage = "5Gi";
      storageClassName = "ceph-block";
    };
    elastic = {
      enabled = true;
      storage = "10Gi";
      storageClassName = "ceph-block";
      javaOpts = "-Xms512m -Xmx512m";
      resources.limits.memory = "2Gi";
    };
  };

  valuesFile = (pkgs.formats.yaml {}).generate "huly-values.yaml" values;

  hulyChart = pkgs.runCommand "huly-chart.yaml" {
    nativeBuildInputs = [pkgs.kubernetes-helm pkgs.python3];
    passAsFile = ["patchScript"];
    patchScript = ''
      import pathlib, sys

      raw = pathlib.Path("raw.yaml").read_text()
      docs = []
      for doc in raw.split("\n---\n"):
          doc = doc.strip()
          if not doc:
              continue
          # Drop the chart-managed secret (huly-secret): created at runtime
          # by k8s-secrets-inject from sops + Ceph RGW credentials instead.
          if "kind: Secret" in doc and "name: huly-secret" in doc:
              continue
          # Templates omit metadata.namespace — inject it after every
          # metadata: line so kubectl apply lands objects in huly.
          lines = []
          for line in doc.split("\n"):
              lines.append(line)
              if line == "metadata:":
                  lines.append("  namespace: huly")
          docs.append("\n".join(lines))
      pathlib.Path(sys.argv[1]).write_text("\n---\n".join(docs) + "\n")
    '';
  } ''
    helm template huly ${../../../lib/helm/charts/vendored/huly} \
      --namespace huly \
      --values ${valuesFile} \
      > raw.yaml
    python3 $patchScriptPath $out
    echo "rendered $(grep -c '^kind:' $out) resources (huly-secret stripped, namespace injected)"
  '';
in {
  chartFiles = {
    "23z-huly-chart.yaml" = hulyChart;
  };

  inlineFiles = {
    "23-huly-namespace.yaml" = namespace;
    "23a-huly-rgw-user.yaml" = rgwUser;
    "23b-huly-rgw-buckets.yaml" = rgwBucketJob;
    "23c-huly-cockroach-init.yaml" = cockroachInitJob;
  };

  order = [
    "23-huly-namespace.yaml"
    "23a-huly-rgw-user.yaml"
    "23b-huly-rgw-buckets.yaml"
    "23c-huly-cockroach-init.yaml"
    "23z-huly-chart.yaml"
  ];
}
