# Nextcloud file collaboration suite
# Namespace + CNPG + Redis + persistent application/data volume + ingress
# (cloud.voltrum.co)
#
# Secrets (k8s-secrets-inject from SOPS):
#   nextcloud-db-secret       CNPG initdb + application DB credentials
#   nextcloud-admin-secret    initial Nextcloud administrator password
{
  pkgs,
  lib,
}: let
  d = import ../../../lib/domain.nix;

  # Backbone nodes are tainted so application workloads must explicitly opt in.
  tolerations = "      tolerations:\n        - key: role\n          operator: Equal\n          value: backbone\n          effect: NoSchedule\n        - key: infra\n          operator: Equal\n          value: \"true\"\n          effect: NoSchedule";

  namespace = ''
apiVersion: v1
kind: Namespace
metadata:
  name: nextcloud
  labels:
    app.kubernetes.io/name: nextcloud
'';

  pvc = ''
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-data
  namespace: nextcloud
  labels:
    app.kubernetes.io/name: nextcloud
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 100Gi
'';

  cluster = ''
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: nextcloud-db
  namespace: nextcloud
  labels:
    app.kubernetes.io/name: nextcloud
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie
  storage:
    storageClass: ceph-block
    size: 10Gi
  resources:
    requests:
      cpu: 50m
      memory: 256Mi
    limits:
      cpu: "1"
      memory: 1Gi
  bootstrap:
    initdb:
      database: nextcloud
      owner: nextcloud
      secret:
        name: nextcloud-db-secret
  postgresql:
    pg_hba:
      - host all all 0.0.0.0/0 md5
      - host all all ::0/0 md5
  backup:
    barmanObjectStore:
      destinationPath: "s3://cnpg-backups/nextcloud-db"
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
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: nextcloud-db-hourly
  namespace: nextcloud
  labels:
    app.kubernetes.io/name: nextcloud
spec:
  schedule: "0 30 * * * *"
  immediate: true
  backupOwnerReference: cluster
  method: barmanObjectStore
  cluster:
    name: nextcloud-db
'';

  redis = ''
apiVersion: v1
kind: Service
metadata:
  name: nextcloud-redis
  namespace: nextcloud
  labels:
    app.kubernetes.io/name: nextcloud-redis
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: nextcloud-redis
  ports:
    - name: redis
      port: 6379
      targetPort: redis
      protocol: TCP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nextcloud-redis
  namespace: nextcloud
  labels:
    app.kubernetes.io/name: nextcloud-redis
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: nextcloud-redis
  template:
    metadata:
      labels:
        app.kubernetes.io/name: nextcloud-redis
    spec:
${tolerations}
      automountServiceAccountToken: false
      containers:
        - name: redis
          image: redis:7.4-alpine
          imagePullPolicy: IfNotPresent
          args:
            - redis-server
            - --appendonly
            - "no"
            - --maxmemory
            - 256mb
            - --maxmemory-policy
            - allkeys-lru
          ports:
            - name: redis
              containerPort: 6379
              protocol: TCP
          readinessProbe:
            exec:
              command: ["redis-cli", "ping"]
            periodSeconds: 10
            timeoutSeconds: 5
          livenessProbe:
            exec:
              command: ["redis-cli", "ping"]
            initialDelaySeconds: 15
            periodSeconds: 20
            timeoutSeconds: 5
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 384Mi
'';

  deployment = ''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nextcloud
  namespace: nextcloud
  labels:
    app.kubernetes.io/name: nextcloud
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: nextcloud
  template:
    metadata:
      labels:
        app.kubernetes.io/name: nextcloud
    spec:
${tolerations}
      automountServiceAccountToken: false
      securityContext:
        fsGroup: 33
      initContainers:
        - name: wait-db
          image: busybox:1.37
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - until nc -z nextcloud-db-rw 5432; do echo waiting for postgres; sleep 2; done
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 50m
              memory: 32Mi
      containers:
        - name: nextcloud
          image: nextcloud:34.0.3-apache
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          env:
            - name: POSTGRES_HOST
              value: nextcloud-db-rw.nextcloud.svc.cluster.local
            - name: POSTGRES_DB
              value: nextcloud
            - name: POSTGRES_USER
              value: nextcloud
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: nextcloud-db-secret
                  key: password
            - name: NEXTCLOUD_ADMIN_USER
              value: admin
            - name: NEXTCLOUD_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: nextcloud-admin-secret
                  key: password
            - name: NEXTCLOUD_TRUSTED_DOMAINS
              value: ${d.host "cloud"}
            - name: NEXTCLOUD_DATA_DIR
              value: /var/www/html/data
            - name: REDIS_HOST
              value: nextcloud-redis
            - name: REDIS_HOST_PORT
              value: "6379"
            - name: APACHE_DISABLE_REWRITE_IP
              value: "1"
            - name: TRUSTED_PROXIES
              value: "10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
            - name: OVERWRITEHOST
              value: ${d.host "cloud"}
            - name: OVERWRITEPROTOCOL
              value: https
            - name: OVERWRITECLIURL
              value: ${d.url "cloud"}
            - name: PHP_MEMORY_LIMIT
              value: 1024M
            - name: PHP_UPLOAD_LIMIT
              value: 10G
            - name: APACHE_BODY_LIMIT
              value: "0"
            - name: NEXTCLOUD_INIT_HTACCESS
              value: "true"
          volumeMounts:
            - name: nextcloud-data
              mountPath: /var/www/html
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 2Gi
          startupProbe:
            httpGet:
              path: /status.php
              port: http
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 60
          readinessProbe:
            httpGet:
              path: /status.php
              port: http
            periodSeconds: 10
            timeoutSeconds: 5
          livenessProbe:
            httpGet:
              path: /status.php
              port: http
            initialDelaySeconds: 60
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 6
        - name: cron
          image: nextcloud:34.0.3-apache
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
              until [ -f /var/www/html/status.php ]; do sleep 5; done
              while true; do
                php -f /var/www/html/cron.php
                sleep 300
              done
          securityContext:
            runAsNonRoot: true
            runAsUser: 33
            runAsGroup: 33
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: nextcloud-data
              mountPath: /var/www/html
          resources:
            requests:
              cpu: 25m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
      volumes:
        - name: nextcloud-data
          persistentVolumeClaim:
            claimName: nextcloud-data
'';

  service = ''
apiVersion: v1
kind: Service
metadata:
  name: nextcloud
  namespace: nextcloud
  labels:
    app.kubernetes.io/name: nextcloud
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: nextcloud
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
'';

  ingress = ''
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nextcloud
  namespace: nextcloud
  labels:
    app.kubernetes.io/name: nextcloud
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
    - host: ${d.host "cloud"}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nextcloud
                port:
                  number: 80
'';
in {
  chartFiles = {};

  inlineFiles = {
    "23-nextcloud-namespace.yaml" = namespace;
    "23a-nextcloud-pvc.yaml" = pvc;
    "23b-nextcloud-cnpg.yaml" = cluster;
    "23c-nextcloud-redis.yaml" = redis;
    "23d-nextcloud-deployment.yaml" = deployment;
    "23e-nextcloud-service.yaml" = service;
    "23f-nextcloud-ingress.yaml" = ingress;
  };

  order = [
    "23-nextcloud-namespace.yaml"
    "23a-nextcloud-pvc.yaml"
    "23b-nextcloud-cnpg.yaml"
    "23c-nextcloud-redis.yaml"
    "23d-nextcloud-deployment.yaml"
    "23e-nextcloud-service.yaml"
    "23f-nextcloud-ingress.yaml"
  ];
}
