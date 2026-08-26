# Harbor bootstrap module
# Harbor namespace + chart + PVCs + ingress
{
  pkgs,
  lib,
  existingCharts,
}: let
  d = import ../../../lib/domain.nix;
  harborChart = existingCharts.harbor;

  harborNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: harbor
      labels:
        app.kubernetes.io/name: harbor
  '';

  harborPvcs = ''
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: harbor-registry-ceph
      namespace: harbor
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 100Gi
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: harbor-jobservice-ceph
      namespace: harbor
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 1Gi
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: harbor-database-ceph
      namespace: harbor
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 1Gi
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: harbor-redis-ceph
      namespace: harbor
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 1Gi
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: harbor-trivy-ceph
      namespace: harbor
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 5Gi
  '';

  # Idempotently ensure the Harbor 'library' project (CI-pushed app images)
  # has a retention policy: keep the 10 most recently pushed artifacts per
  # repository, evaluated daily by Harbor. Without this, every CI push stays
  # in the registry forever (node-side kubelet image GC handles stale cached
  # images, but the registry itself needs its own retention rule).
  # The 'dockerhub' proxy-cache project already has a 7-days-since-last-pull
  # policy and is intentionally left untouched.
  harborRetention = ''
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: harbor-retention-ensure
      namespace: harbor
    data:
      ensure.sh: |
        #!/bin/sh
        set -eu
        API="http://harbor-core/api/v2.0"
        AUTH="-u admin:$HARBOR_ADMIN_PASSWORD"

        pid=$(curl -sf $AUTH -H 'accept: application/json' \
          "$API/projects?name=library" | sed -n 's/.*"project_id":\([0-9]*\).*/\1/p' | head -1)
        [ -n "$pid" ] || { echo "project 'library' not found"; exit 1; }

        # Find this project's existing retention policy id. The API has no
        # "get by project" endpoint, so scan policy ids and match scope.ref.
        rid=""
        i=1
        while [ "$i" -le 50 ]; do
          p=$(curl -sf $AUTH -H 'accept: application/json' "$API/retentions/$i" || true)
          if echo "$p" | grep -q "\"ref\":$pid}"; then rid=$i; break; fi
          i=$((i + 1))
        done

        rules='[{"action":"retain","template":"latestPushedK","params":{"latestPushedK":10},"scope_selectors":{"repository":[{"kind":"doublestar","decoration":"repoMatches","pattern":"**"}]},"tag_selectors":[{"kind":"doublestar","decoration":"matches","pattern":"**"}]}]'

        # PUT and POST both require the scope field in the body.
        body="{\"algorithm\":\"or\",\"rules\":$rules,\"scope\":{\"level\":\"project\",\"ref\":$pid},\"trigger\":{\"kind\":\"Schedule\",\"settings\":{\"cron\":\"0 0 0 * * *\"}}}"

        if [ -n "$rid" ]; then
          echo "updating retention policy $rid on project library"
          curl -sf $AUTH -X PUT -H 'content-type: application/json' \
            -d "$body" "$API/retentions/$rid"
        else
          echo "creating retention policy on project library"
          curl -sf $AUTH -X POST -H 'content-type: application/json' \
            -d "$body" "$API/retentions"
        fi
        echo "retention policy ensured"
    ---
    apiVersion: batch/v1
    kind: CronJob
    metadata:
      name: harbor-retention-ensure
      namespace: harbor
      labels:
        app.kubernetes.io/name: harbor
    spec:
      schedule: "0 3 * * *"
      concurrencyPolicy: Forbid
      successfulJobsHistoryLimit: 1
      failedJobsHistoryLimit: 3
      jobTemplate:
        spec:
          backoffLimit: 2
          template:
            spec:
              restartPolicy: Never
              containers:
                - name: ensure
                  image: docker.io/curlimages/curl:8.16.0
                  command: ["/bin/sh", "/scripts/ensure.sh"]
                  env:
                    - name: HARBOR_ADMIN_PASSWORD
                      valueFrom:
                        secretKeyRef:
                          name: harbor-admin-secret
                          key: password
                  volumeMounts:
                    - name: script
                      mountPath: /scripts
                  resources:
                    requests:
                      cpu: 10m
                      memory: 16Mi
                    limits:
                      memory: 64Mi
              volumes:
                - name: script
                  configMap:
                    name: harbor-retention-ensure
                    defaultMode: 0744
  '';

  harborIngress = ''
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: harbor-ingress
      namespace: harbor
      annotations:
        nginx.ingress.kubernetes.io/proxy-body-size: "0"
        nginx.ingress.kubernetes.io/ssl-redirect: "false"
        nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
        nginx.ingress.kubernetes.io/proxy-buffering: "off"
    spec:
      ingressClassName: nginx
      tls:
      - hosts:
        - ${d.host "harbor"}
        secretName: harbor-ingress
      rules:
      - host: ${d.host "harbor"}
        http:
          paths:
          - path: /api/
            pathType: Prefix
            backend:
              service:
                name: harbor-core
                port:
                  number: 80
          - path: /service/
            pathType: Prefix
            backend:
              service:
                name: harbor-core
                port:
                  number: 80
          - path: /v2/
            pathType: Prefix
            backend:
              service:
                name: harbor-core
                port:
                  number: 80
          - path: /c/
            pathType: Prefix
            backend:
              service:
                name: harbor-core
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: harbor-portal
                port:
                  number: 80
  '';
in {
  chartFiles = {
    "11-harbor-chart.yaml" = harborChart;
  };

  inlineFiles = {
    "09-harbor-namespace.yaml" = harborNamespace;
    "09a-harbor-pvcs-ceph.yaml" = harborPvcs;
    "12-harbor-ingress.yaml" = harborIngress;
    "13-harbor-retention.yaml" = harborRetention;
  };

  order = [
    "09-harbor-namespace.yaml"
    "09a-harbor-pvcs-ceph.yaml"
    "11-harbor-chart.yaml"
    "12-harbor-ingress.yaml"
    "13-harbor-retention.yaml"
  ];
}
