# UPG collaborative game-asset storage:
# SFTPGo (SFTP + WebDAV) + Git working tree PVC + debounced auto-commit watcher.
#
# Artists mount/edit via SFTP; changes are committed/pushed to
# forge.voltrum.co/farbeam/upg with Git LFS. No Nextcloud.
#
# Secrets (k8s-secrets-inject from SOPS, or manual apply of secret.template):
#   upg-assets-git          Forgejo token for clone/pull/push
#   upg-assets-sftpgo-users Portable SFTPGo user dump (JSON)
{
  pkgs,
  lib,
}: let
  d = import ../../../lib/domain.nix;

  # Scripts live in the nix repo and are embedded into ConfigMaps.
  watcherScript = builtins.readFile ../../../apps/upg-assets/watcher/git-autocommit.sh;
  bootstrapScript = builtins.readFile ../../../apps/upg-assets/watcher/bootstrap-repo.sh;
  sftpgoConfig = builtins.readFile ../../../apps/upg-assets/sftpgo/sftpgo.json;

  tolerations = "      tolerations:\n        - key: role\n          operator: Equal\n          value: backbone\n          effect: NoSchedule\n        - key: infra\n          operator: Equal\n          value: \"true\"\n          effect: NoSchedule";

  namespace = ''
apiVersion: v1
kind: Namespace
metadata:
  name: upg-assets
  labels:
    app.kubernetes.io/name: upg-assets
'';

  pvcs = ''
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: upg-workspace
  namespace: upg-assets
  labels:
    app.kubernetes.io/name: upg-assets
    app.kubernetes.io/component: workspace
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
  name: upg-sftpgo-data
  namespace: upg-assets
  labels:
    app.kubernetes.io/name: upg-assets
    app.kubernetes.io/component: sftpgo-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 1Gi
'';

  configmaps = ''
apiVersion: v1
kind: ConfigMap
metadata:
  name: upg-assets-scripts
  namespace: upg-assets
  labels:
    app.kubernetes.io/name: upg-assets
data:
  bootstrap-repo.sh: |
${lib.concatMapStrings (line: "    " + line + "\n") (lib.splitString "\n" bootstrapScript)}
  git-autocommit.sh: |
${lib.concatMapStrings (line: "    " + line + "\n") (lib.splitString "\n" watcherScript)}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: upg-sftpgo-config
  namespace: upg-assets
  labels:
    app.kubernetes.io/name: upg-assets
data:
  sftpgo.json: |
${lib.concatMapStrings (line: "    " + line + "\n") (lib.splitString "\n" sftpgoConfig)}
'';

  # Secret placeholders are NOT created here — injected via SOPS / template.
  # Documented in apps/upg-assets/secrets/secret.template.yaml

  statefulset = ''
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: upg-assets
  namespace: upg-assets
  labels:
    app.kubernetes.io/name: upg-assets
spec:
  serviceName: upg-assets
  replicas: 1
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app.kubernetes.io/name: upg-assets
  template:
    metadata:
      labels:
        app.kubernetes.io/name: upg-assets
    spec:
${tolerations}
      securityContext:
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
      automountServiceAccountToken: false
      initContainers:
        - name: bootstrap-git
          image: alpine/git:2.45.2
          imagePullPolicy: IfNotPresent
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -euo pipefail
              apk add --no-cache git-lfs bash curl >/dev/null
              install -m 0755 /scripts/bootstrap-repo.sh /tmp/bootstrap-repo.sh
              export WORKSPACE=/workspace
              export REPO_URL=https://forge.voltrum.co/farbeam/upg.git
              export DEFAULT_BRANCH=main
              export GIT_TOKEN="''${GIT_TOKEN}"
              export GIT_USERNAME="''${GIT_USERNAME:-oauth2}"
              /tmp/bootstrap-repo.sh
          env:
            - name: GIT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: upg-assets-git
                  key: token
            - name: GIT_USERNAME
              valueFrom:
                secretKeyRef:
                  name: upg-assets-git
                  key: username
                  optional: true
          volumeMounts:
            - name: workspace
              mountPath: /workspace
            - name: scripts
              mountPath: /scripts
              readOnly: true
      containers:
        - name: sftpgo
          image: drakkan/sftpgo:v2.6.4-alpine
          imagePullPolicy: IfNotPresent
          args:
            - sftpgo
            - serve
          ports:
            - name: sftp
              containerPort: 2022
              protocol: TCP
            - name: webdav
              containerPort: 10080
              protocol: TCP
            - name: http
              containerPort: 8080
              protocol: TCP
          env:
            - name: SFTPGO_CONFIG_FILE
              value: /etc/sftpgo/sftpgo.json
            - name: SFTPGO_DATA_PROVIDER__CREATE_DEFAULT_ADMIN
              value: "false"
            # Load artist accounts on every start; mode 0 = update existing + add new.
            - name: SFTPGO_LOADDATA_FROM
              value: /etc/sftpgo-users/users.json
            - name: SFTPGO_LOADDATA_CLEAN
              value: "false"
            - name: SFTPGO_LOADDATA_MODE
              value: "0"
          volumeMounts:
            - name: workspace
              mountPath: /workspace
            - name: sftpgo-data
              mountPath: /var/lib/sftpgo
            - name: sftpgo-config
              mountPath: /etc/sftpgo
              readOnly: true
            - name: sftpgo-users
              mountPath: /etc/sftpgo-users
              readOnly: true
          readinessProbe:
            tcpSocket:
              port: sftp
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            tcpSocket:
              port: sftp
            initialDelaySeconds: 20
            periodSeconds: 30
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: "1"
              memory: 1Gi
        - name: git-watcher
          image: alpine:3.21
          imagePullPolicy: IfNotPresent
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -euo pipefail
              apk add --no-cache git git-lfs bash inotify-tools curl util-linux >/dev/null
              git lfs install --system >/dev/null 2>&1 || true
              install -m 0755 /scripts/git-autocommit.sh /tmp/git-autocommit.sh
              export WORKSPACE=/workspace
              export DEBOUNCE_SECONDS=45
              export GIT_AUTHOR_NAME="UPG Assets Bot"
              export GIT_AUTHOR_EMAIL="assets-bot@voltrum.co"
              # Keep tokenized insteadOf in this process environment via bootstrap helper config.
              REPO_URL=https://forge.voltrum.co/farbeam/upg.git
              AUTH_URL="https://''${GIT_USERNAME}:''${GIT_TOKEN}@forge.voltrum.co/farbeam/upg.git"
              git config --global --add safe.directory /workspace
              git config --global "url.''${AUTH_URL}.insteadOf" "$REPO_URL"
              cd /workspace
              # Never persist the token in remote.origin.url — only via insteadOf.
              git remote set-url origin "$REPO_URL" 2>/dev/null || true
              exec /tmp/git-autocommit.sh
          env:
            - name: GIT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: upg-assets-git
                  key: token
            - name: GIT_USERNAME
              valueFrom:
                secretKeyRef:
                  name: upg-assets-git
                  key: username
                  optional: true
          volumeMounts:
            - name: workspace
              mountPath: /workspace
            - name: scripts
              mountPath: /scripts
              readOnly: true
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: "500m"
              memory: 512Mi
      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: upg-workspace
        - name: sftpgo-data
          persistentVolumeClaim:
            claimName: upg-sftpgo-data
        - name: scripts
          configMap:
            name: upg-assets-scripts
            defaultMode: 0755
        - name: sftpgo-config
          configMap:
            name: upg-sftpgo-config
        - name: sftpgo-users
          secret:
            secretName: upg-assets-sftpgo-users
'';

  service = ''
apiVersion: v1
kind: Service
metadata:
  name: upg-assets
  namespace: upg-assets
  labels:
    app.kubernetes.io/name: upg-assets
  annotations:
    # Optional: point a Cloudflare TCP hostname (assets-sftp.voltrum.co) here later.
    external-dns.alpha.kubernetes.io/hostname: assets-sftp.${d.domain}
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: upg-assets
  ports:
    - name: sftp
      port: 2022
      targetPort: sftp
      nodePort: 32202
      protocol: TCP
    - name: webdav
      port: 10080
      targetPort: webdav
      protocol: TCP
    - name: http
      port: 8080
      targetPort: http
      protocol: TCP
'';

  ingress = ''
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: upg-assets-webdav
  namespace: upg-assets
  labels:
    app.kubernetes.io/name: upg-assets
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
    - host: ${d.host "assets"}
      http:
        paths:
          - path: /webdav
            pathType: Prefix
            backend:
              service:
                name: upg-assets
                port:
                  number: 10080
          - path: /
            pathType: Prefix
            backend:
              service:
                name: upg-assets
                port:
                  number: 8080
'';
in {
  chartFiles = {};

  inlineFiles = {
    "25-upg-assets-namespace.yaml" = namespace;
    "25a-upg-assets-pvcs.yaml" = pvcs;
    "25b-upg-assets-configmaps.yaml" = configmaps;
    "25c-upg-assets-statefulset.yaml" = statefulset;
    "25d-upg-assets-service.yaml" = service;
    "25e-upg-assets-ingress.yaml" = ingress;
  };

  order = [
    "25-upg-assets-namespace.yaml"
    "25a-upg-assets-pvcs.yaml"
    "25b-upg-assets-configmaps.yaml"
    "25c-upg-assets-statefulset.yaml"
    "25d-upg-assets-service.yaml"
    "25e-upg-assets-ingress.yaml"
  ];
}
