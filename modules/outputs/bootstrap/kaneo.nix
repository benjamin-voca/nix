# Kaneo (project management / kanban — combined API + web container)
# Namespace + CNPG + Deployment + Service + Ingress (kaneo.voltrum.co)
#
# Secrets (k8s-secrets-inject from sops):
#   kaneo-db-secret     CNPG initdb (username/password/dbname)
#   kaneo-app-secrets   DATABASE_URL + AUTH_SECRET (JWT signing, >=32 chars)
#
# Object storage is intentionally not configured: uploads in task
# descriptions/comments are optional in Kaneo. To enable them later, add
# an RGW user + bucket and set the S3_* env vars on the deployment.
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
  name: kaneo
  labels:
    app.kubernetes.io/name: kaneo
'';

  cluster = ''
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: kaneo-db
  namespace: kaneo
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
      database: kaneo
      owner: kaneo
      secret:
        name: kaneo-db-secret
  postgresql:
    pg_hba:
      - host all all 0.0.0.0/0 md5
      - host all all ::0/0 md5
  backup:
    barmanObjectStore:
      destinationPath: "s3://cnpg-backups/kaneo-db"
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
  name: kaneo
  namespace: kaneo
  labels:
    app: kaneo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kaneo
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: kaneo
    spec:
${tolerations}
      initContainers:
        - name: wait-db
          image: busybox:1.37
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - until nc -z kaneo-db-rw 5432; do echo waiting for postgres; sleep 2; done
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 50m
              memory: 32Mi
      containers:
        - name: kaneo
          # Combined API + web container; listens on 5173 and serves /api.
          # Upstream publishes no release tags to GHCR — "latest" is the
          # only supported tag (see compose.yml in usekaneo/kaneo docs).
          image: ghcr.io/usekaneo/kaneo:latest
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 5173
              protocol: TCP
          env:
            - name: KANEO_CLIENT_URL
              value: ${d.url "kaneo"}
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: kaneo-app-secrets
                  key: DATABASE_URL
            - name: AUTH_SECRET
              valueFrom:
                secretKeyRef:
                  name: kaneo-app-secrets
                  key: AUTH_SECRET
            # Public instance: no anonymous guest sign-in button
            - name: DISABLE_GUEST_ACCESS
              value: "true"
          resources:
            requests:
              cpu: 50m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          startupProbe:
            httpGet:
              path: /api/health
              port: http
            periodSeconds: 5
            failureThreshold: 36
          readinessProbe:
            httpGet:
              path: /api/health
              port: http
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          livenessProbe:
            httpGet:
              path: /api/health
              port: http
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 6
'';

  service = ''
apiVersion: v1
kind: Service
metadata:
  name: kaneo
  namespace: kaneo
spec:
  type: ClusterIP
  selector:
    app: kaneo
  ports:
    - name: http
      port: 5173
      targetPort: http
      protocol: TCP
'';

  ingress = ''
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kaneo
  namespace: kaneo
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  rules:
    - host: ${d.host "kaneo"}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kaneo
                port:
                  number: 5173
'';
in {
  chartFiles = {};

  inlineFiles = {
    "23-kaneo-namespace.yaml" = namespace;
    "23a-kaneo-cnpg.yaml" = cluster;
    "23b-kaneo-deployment.yaml" = deployment;
    "23c-kaneo-service.yaml" = service;
    "23d-kaneo-ingress.yaml" = ingress;
  };

  order = [
    "23-kaneo-namespace.yaml"
    "23a-kaneo-cnpg.yaml"
    "23b-kaneo-deployment.yaml"
    "23c-kaneo-service.yaml"
    "23d-kaneo-ingress.yaml"
  ];
}
