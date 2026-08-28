# NocoDB (Airtable-like spreadsheet UI)
# Namespace + CNPG + PVC + Deployment + Service + Ingress (noco.voltrum.co)
#
# Secrets (k8s-secrets-inject from sops):
#   nocodb-db-secret     CNPG initdb (username/password/dbname)
#   nocodb-app-secrets   NC_AUTH_JWT_SECRET + NC_DB
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
  name: nocodb
  labels:
    app.kubernetes.io/name: nocodb
'';

  pvc = ''
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nocodb-data
  namespace: nocodb
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 10Gi
'';

  cluster = ''
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: nocodb-db
  namespace: nocodb
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie
  enableSuperuserAccess: true
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
      database: nocodb
      owner: nocodb
      secret:
        name: nocodb-db-secret
  postgresql:
    pg_hba:
      - host all all 0.0.0.0/0 md5
      - host all all ::0/0 md5
  backup:
    barmanObjectStore:
      destinationPath: "s3://cnpg-backups/nocodb-db"
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
  name: nocodb
  namespace: nocodb
  labels:
    app: nocodb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nocodb
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nocodb
    spec:
${tolerations}
      securityContext:
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      initContainers:
        - name: wait-db
          image: busybox:1.37
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - until nc -z nocodb-db-rw 5432; do echo waiting for postgres; sleep 2; done
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 50m
              memory: 32Mi
      containers:
        - name: nocodb
          image: nocodb/nocodb:2026.08.1
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          env:
            - name: PORT
              value: "8080"
            - name: NC_PUBLIC_URL
              value: ${d.url "noco"}
            - name: NC_DISABLE_TELE
              value: "true"
            - name: NC_AUTH_JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: nocodb-app-secrets
                  key: NC_AUTH_JWT_SECRET
            - name: NC_DB
              valueFrom:
                secretKeyRef:
                  name: nocodb-app-secrets
                  key: NC_DB
          volumeMounts:
            - name: data
              mountPath: /usr/app/data
          resources:
            requests:
              cpu: 50m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          startupProbe:
            httpGet:
              path: /api/v1/health
              port: http
            periodSeconds: 5
            failureThreshold: 36
          readinessProbe:
            httpGet:
              path: /api/v1/health
              port: http
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          livenessProbe:
            httpGet:
              path: /api/v1/health
              port: http
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 6
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: nocodb-data
'';

  service = ''
apiVersion: v1
kind: Service
metadata:
  name: nocodb
  namespace: nocodb
spec:
  type: ClusterIP
  selector:
    app: nocodb
  ports:
    - name: http
      port: 8080
      targetPort: http
      protocol: TCP
'';

  ingress = ''
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nocodb
  namespace: nocodb
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/websocket-services: "nocodb"
spec:
  ingressClassName: nginx
  rules:
    - host: ${d.host "noco"}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nocodb
                port:
                  number: 8080
'';
in {
  chartFiles = {};

  inlineFiles = {
    "23-nocodb-namespace.yaml" = namespace;
    "23a-nocodb-pvc.yaml" = pvc;
    "23b-nocodb-cnpg.yaml" = cluster;
    "23c-nocodb-deployment.yaml" = deployment;
    "23d-nocodb-service.yaml" = service;
    "23e-nocodb-ingress.yaml" = ingress;
  };

  order = [
    "23-nocodb-namespace.yaml"
    "23a-nocodb-pvc.yaml"
    "23b-nocodb-cnpg.yaml"
    "23c-nocodb-deployment.yaml"
    "23d-nocodb-service.yaml"
    "23e-nocodb-ingress.yaml"
  ];
}
