# n8n workflow automation
# Namespace + CNPG + PVC + Deployment + Service + Ingress (n8n.voltrum.co)
#
# Secrets (k8s-secrets-inject from sops):
#   n8n-db-secret     CNPG initdb (username/password/dbname)
#   n8n-app-secrets   N8N_ENCRYPTION_KEY + DB_POSTGRESDB_PASSWORD
{
  pkgs,
  lib,
}: let
  d = import ../../../lib/domain.nix;
  tolerations = "      tolerations:\n        - key: role\n          operator: Equal\n          value: backbone\n          effect: NoSchedule\n        - key: infra\n          operator: Equal\n          value: \"true\"\n          effect: NoSchedule";

  namespace = ''
apiVersion: v1
kind: Namespace
metadata:
  name: n8n
  labels:
    app.kubernetes.io/name: n8n
'';

  pvc = ''
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: n8n-data
  namespace: n8n
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 5Gi
'';

  cluster = ''
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: n8n-db
  namespace: n8n
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie
  enableSuperuserAccess: true
  storage:
    storageClass: ceph-block
    size: 5Gi
  resources:
    requests:
      cpu: 50m
      memory: 256Mi
    limits:
      cpu: "1"
      memory: 1Gi
  bootstrap:
    initdb:
      database: n8n
      owner: n8n
      secret:
        name: n8n-db-secret
  postgresql:
    pg_hba:
      - host all all 0.0.0.0/0 md5
      - host all all ::0/0 md5
  backup:
    barmanObjectStore:
      destinationPath: "s3://cnpg-backups/n8n-db"
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
'';

  deployment = ''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: n8n
  labels:
    app: n8n
spec:
  replicas: 1
  selector:
    matchLabels:
      app: n8n
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: n8n
    spec:
${tolerations}
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
        runAsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      initContainers:
        - name: wait-db
          image: busybox:1.37
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - until nc -z n8n-db-rw 5432; do echo waiting for postgres; sleep 2; done
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 50m
              memory: 32Mi
      containers:
        - name: n8n
          image: docker.n8n.io/n8nio/n8n:2.12.3
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 5678
              protocol: TCP
          env:
            - name: DB_TYPE
              value: postgresdb
            - name: DB_POSTGRESDB_HOST
              value: n8n-db-rw.n8n.svc.cluster.local
            - name: DB_POSTGRESDB_PORT
              value: "5432"
            - name: DB_POSTGRESDB_DATABASE
              value: n8n
            - name: DB_POSTGRESDB_USER
              value: n8n
            - name: DB_POSTGRESDB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: n8n-db-secret
                  key: password
            - name: DB_POSTGRESDB_SSL_ENABLED
              value: "false"
            - name: N8N_ENCRYPTION_KEY
              valueFrom:
                secretKeyRef:
                  name: n8n-app-secrets
                  key: N8N_ENCRYPTION_KEY
            - name: N8N_HOST
              value: ${d.host "n8n"}
            - name: N8N_PORT
              value: "5678"
            - name: N8N_PROTOCOL
              value: https
            - name: N8N_EDITOR_BASE_URL
              value: ${d.url "n8n"}/
            - name: WEBHOOK_URL
              value: ${d.url "n8n"}/
            - name: N8N_PROXY_HOPS
              value: "1"
            - name: N8N_SECURE_COOKIE
              value: "true"
            - name: N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS
              value: "true"
            - name: N8N_DIAGNOSTICS_ENABLED
              value: "false"
            - name: N8N_HIRING_BANNER
              value: "false"
            - name: GENERIC_TIMEZONE
              value: Europe/Belgrade
            - name: TZ
              value: Europe/Belgrade
            - name: EXECUTIONS_DATA_PRUNE
              value: "true"
            - name: EXECUTIONS_DATA_MAX_AGE
              value: "336"
            - name: NODE_ENV
              value: production
          volumeMounts:
            - name: data
              mountPath: /home/node/.n8n
          resources:
            requests:
              cpu: 50m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          startupProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 5
            failureThreshold: 36
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 10
            timeoutSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 6
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: n8n-data
'';

  service = ''
apiVersion: v1
kind: Service
metadata:
  name: n8n
  namespace: n8n
spec:
  type: ClusterIP
  selector:
    app: n8n
  ports:
    - name: http
      port: 5678
      targetPort: http
      protocol: TCP
'';

  ingress = ''
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n
  namespace: n8n
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/websocket-services: "n8n"
spec:
  ingressClassName: nginx
  rules:
    - host: ${d.host "n8n"}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: n8n
                port:
                  number: 5678
'';
in {
  chartFiles = {};

  inlineFiles = {
    "22-n8n-namespace.yaml" = namespace;
    "22a-n8n-pvc.yaml" = pvc;
    "22b-n8n-cnpg.yaml" = cluster;
    "22c-n8n-deployment.yaml" = deployment;
    "22d-n8n-service.yaml" = service;
    "22e-n8n-ingress.yaml" = ingress;
  };

  order = [
    "22-n8n-namespace.yaml"
    "22a-n8n-pvc.yaml"
    "22b-n8n-cnpg.yaml"
    "22c-n8n-deployment.yaml"
    "22d-n8n-service.yaml"
    "22e-n8n-ingress.yaml"
  ];
}
