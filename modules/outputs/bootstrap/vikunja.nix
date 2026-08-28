# Vikunja (to-do / task management, unified API+frontend image)
# Namespace + CNPG + PVC + Deployment + Service + Ingress (vikunja.voltrum.co)
#
# Secrets (k8s-secrets-inject from sops):
#   vikunja-db-secret     CNPG initdb (username/password/dbname)
#   vikunja-app-secrets   VIKUNJA_SERVICE_SECRET (JWT signing)
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
  name: vikunja
  labels:
    app.kubernetes.io/name: vikunja
'';

  pvc = ''
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vikunja-files
  namespace: vikunja
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
  name: vikunja-db
  namespace: vikunja
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
      database: vikunja
      owner: vikunja
      secret:
        name: vikunja-db-secret
  postgresql:
    pg_hba:
      - host all all 0.0.0.0/0 md5
      - host all all ::0/0 md5
  backup:
    barmanObjectStore:
      destinationPath: "s3://cnpg-backups/vikunja-db"
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
  name: vikunja
  namespace: vikunja
  labels:
    app: vikunja
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vikunja
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: vikunja
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
            - until nc -z vikunja-db-rw 5432; do echo waiting for postgres; sleep 2; done
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 50m
              memory: 32Mi
      containers:
        - name: vikunja
          # Unified image: API + embedded frontend, runs as uid 1000 (scratch, no shell)
          image: vikunja/vikunja:2.5.0
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 3456
              protocol: TCP
          env:
            - name: VIKUNJA_SERVICE_PUBLICURL
              value: ${d.url "vikunja"}
            - name: VIKUNJA_SERVICE_SECRET
              valueFrom:
                secretKeyRef:
                  name: vikunja-app-secrets
                  key: VIKUNJA_SERVICE_SECRET
            - name: VIKUNJA_DATABASE_TYPE
              value: postgres
            - name: VIKUNJA_DATABASE_HOST
              value: vikunja-db-rw.vikunja.svc.cluster.local:5432
            - name: VIKUNJA_DATABASE_USER
              valueFrom:
                secretKeyRef:
                  name: vikunja-db-secret
                  key: username
            - name: VIKUNJA_DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: vikunja-db-secret
                  key: password
            - name: VIKUNJA_DATABASE_DATABASE
              value: vikunja
          volumeMounts:
            - name: files
              mountPath: /app/vikunja/files
          resources:
            requests:
              cpu: 50m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          startupProbe:
            httpGet:
              path: /api/v1/info
              port: http
            periodSeconds: 5
            failureThreshold: 72
          readinessProbe:
            httpGet:
              path: /api/v1/info
              port: http
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          livenessProbe:
            httpGet:
              path: /api/v1/info
              port: http
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 6
      volumes:
        - name: files
          persistentVolumeClaim:
            claimName: vikunja-files
'';

  service = ''
apiVersion: v1
kind: Service
metadata:
  name: vikunja
  namespace: vikunja
spec:
  type: ClusterIP
  selector:
    app: vikunja
  ports:
    - name: http
      port: 3456
      targetPort: http
      protocol: TCP
'';

  ingress = ''
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vikunja
  namespace: vikunja
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
    - host: ${d.host "vikunja"}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: vikunja
                port:
                  number: 3456
'';
in {
  chartFiles = {};

  inlineFiles = {
    "23-vikunja-namespace.yaml" = namespace;
    "23a-vikunja-pvc.yaml" = pvc;
    "23b-vikunja-cnpg.yaml" = cluster;
    "23c-vikunja-deployment.yaml" = deployment;
    "23d-vikunja-service.yaml" = service;
    "23e-vikunja-ingress.yaml" = ingress;
  };

  order = [
    "23-vikunja-namespace.yaml"
    "23a-vikunja-pvc.yaml"
    "23b-vikunja-cnpg.yaml"
    "23c-vikunja-deployment.yaml"
    "23d-vikunja-service.yaml"
    "23e-vikunja-ingress.yaml"
  ];
}
