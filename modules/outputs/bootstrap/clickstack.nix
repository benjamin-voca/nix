# ClickStack bootstrap module
# Namespace + self-managed ClickHouse/Mongo/OTel-collector + HyperDX chart
# + ingresses (UI + public OTLP endpoint for Roblox ingestion).
#
# Secrets: created on the host by k8s-secrets-inject (sops clickstack-* keys):
#   - clickstack-secrets          env/config for HyperDX + collector + Mongo
#   - clickstack-clickhouse-users users.d XML (hashed app/otelcollector users)
# The ClickHouse STS mounts the users secret and hot-reloads on change.
{lib, existingCharts}: let
  # Exact-indent tolerations for backbone taints (double-quoted string so
  # nix '' dedent can't shift it).
  tolerations = "      tolerations:\n        - key: role\n          operator: Equal\n          value: backbone\n          effect: NoSchedule\n        - key: infra\n          operator: Equal\n          value: \"true\"\n          effect: NoSchedule";

  clickstackNamespace = ''
apiVersion: v1
kind: Namespace
metadata:
  name: clickstack
  labels:
    app.kubernetes.io/name: clickstack
'';

  # ── ClickHouse ───────────────────────────────────────────────────────────────
  clickhouseServices = ''
apiVersion: v1
kind: Service
metadata:
  name: clickhouse-headless
  namespace: clickstack
  labels:
    app.kubernetes.io/name: clickhouse
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app.kubernetes.io/name: clickhouse
  ports:
    - name: http
      port: 8123
    - name: native
      port: 9000
---
apiVersion: v1
kind: Service
metadata:
  name: clickhouse
  namespace: clickstack
  labels:
    app.kubernetes.io/name: clickhouse
spec:
  selector:
    app.kubernetes.io/name: clickhouse
  ports:
    - name: http
      port: 8123
    - name: native
      port: 9000
    - name: metrics
      port: 9363
'';

  # Single-node ClickHouse with the ClickStack user model:
  #   app           (UI browsing)      — created via mounted users.d secret
  #   otelcollector (ingestion/schema) — created via mounted users.d secret
  clickhouseStatefulSet = ''
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: clickhouse
  namespace: clickstack
  labels:
    app.kubernetes.io/name: clickhouse
spec:
  serviceName: clickhouse-headless
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: clickhouse
  template:
    metadata:
      labels:
        app.kubernetes.io/name: clickhouse
    spec:
${tolerations}
      securityContext:
        fsGroup: 101
      containers:
        - name: clickhouse
          image: clickhouse/clickhouse-server:25.7-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8123
            - name: native
              containerPort: 9000
            - name: metrics
              containerPort: 9363
          volumeMounts:
            - name: data
              mountPath: /var/lib/clickhouse
            - name: users-d
              mountPath: /etc/clickhouse-server/users.d
          env:
            - name: CLICKHOUSE_DB
              value: default
          resources:
            requests:
              cpu: 250m
              memory: 1Gi
            limits:
              cpu: "1500m"
              memory: 2560Mi
          readinessProbe:
            httpGet:
              path: /ping
              port: 8123
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 3
          livenessProbe:
            httpGet:
              path: /ping
              port: 8123
            initialDelaySeconds: 30
            periodSeconds: 15
            timeoutSeconds: 5
            failureThreshold: 6
      volumes:
        - name: users-d
          secret:
            secretName: clickstack-clickhouse-users
            items:
              - key: users.xml
                path: users.xml
            defaultMode: 0644
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: ceph-block
        resources:
          requests:
            storage: 50Gi
'';

  # ── MongoDB (HyperDX app state) ──────────────────────────────────────────────
  mongoDeployment = ''
apiVersion: v1
kind: Service
metadata:
  name: mongo
  namespace: clickstack
  labels:
    app.kubernetes.io/name: mongo
spec:
  selector:
    app.kubernetes.io/name: mongo
  ports:
    - name: mongo
      port: 27017
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongo
  namespace: clickstack
  labels:
    app.kubernetes.io/name: mongo
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: mongo
  template:
    metadata:
      labels:
        app.kubernetes.io/name: mongo
    spec:
${tolerations}
      containers:
        - name: mongo
          image: mongo:5.0
          imagePullPolicy: IfNotPresent
          args: ["--wiredTigerCacheSizeGB", "0.25"]
          ports:
            - name: mongo
              containerPort: 27017
          env:
            - name: MONGO_INITDB_ROOT_USERNAME
              value: hyperdx
            - name: MONGO_INITDB_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: clickstack-secrets
                  key: MONGO_PASSWORD
          volumeMounts:
            - name: data
              mountPath: /data/db
          resources:
            requests:
              cpu: 30m
              memory: 256Mi
            limits:
              cpu: "500m"
              memory: 768Mi
          readinessProbe:
            exec:
              command: ["mongosh", "--quiet", "--eval", "db.adminCommand('ping')"]
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 5
          livenessProbe:
            exec:
              command: ["mongosh", "--quiet", "--eval", "db.adminCommand('ping')"]
            initialDelaySeconds: 60
            periodSeconds: 30
            timeoutSeconds: 5
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: mongo-data
'';

  mongoPvc = ''
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongo-data
  namespace: clickstack
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ceph-block
  resources:
    requests:
      storage: 5Gi
'';

  # ── OTel collector (ClickStack distro — creates/updates otel_* schemas) ─────
  collectorDeployment = ''
apiVersion: v1
kind: Service
metadata:
  name: clickstack-otel-collector
  namespace: clickstack
  labels:
    app.kubernetes.io/name: clickstack-otel-collector
spec:
  selector:
    app.kubernetes.io/name: clickstack-otel-collector
  ports:
    - name: otlp-grpc
      port: 4317
    - name: otlp-http
      port: 4318
    - name: health
      port: 13133
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clickstack-otel-collector
  namespace: clickstack
  labels:
    app.kubernetes.io/name: clickstack-otel-collector
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: clickstack-otel-collector
  template:
    metadata:
      labels:
        app.kubernetes.io/name: clickstack-otel-collector
    spec:
${tolerations}
      containers:
        - name: collector
          image: docker.clickhouse.com/clickhouse/clickstack-otel-collector:2.35.0
          imagePullPolicy: IfNotPresent
          ports:
            - name: otlp-grpc
              containerPort: 4317
            - name: otlp-http
              containerPort: 4318
            - name: health
              containerPort: 13133
          envFrom:
            - configMapRef:
                name: clickstack-config
            - secretRef:
                name: clickstack-secrets
          resources:
            requests:
              cpu: 20m
              memory: 64Mi
            limits:
              cpu: "500m"
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /
              port: 13133
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 13133
            initialDelaySeconds: 30
            periodSeconds: 30
'';

  # ── Ingresses (nginx; Cloudflare wildcard *.voltrum.co terminates TLS) ──────
  ingresses = ''
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: clickstack-hyperdx
  namespace: clickstack
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
    - host: hyperdx.voltrum.co
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: clickstack-app
                port:
                  number: 3000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: clickstack-otlp
  namespace: clickstack
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "16m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
spec:
  ingressClassName: nginx
  rules:
    - host: otlp.voltrum.co
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: clickstack-otel-collector
                port:
                  number: 4318
'';
in {
  chartFiles = {
    "13z-clickstack-chart.yaml" = existingCharts.clickstack;
  };

  inlineFiles = {
    "13a-clickstack-namespace.yaml"   = clickstackNamespace;
    "13b-clickhouse-services.yaml"    = clickhouseServices;
    "13c-clickhouse-statefulset.yaml" = clickhouseStatefulSet;
    "13d-mongo.yaml"                  = mongoDeployment;
    "13e-mongo-pvc.yaml"              = mongoPvc;
    "13f-collector.yaml"              = collectorDeployment;
    "13g-ingresses.yaml"              = ingresses;
  };

  order = [
    "13a-clickstack-namespace.yaml"
    "13b-clickhouse-services.yaml"
    "13c-clickhouse-statefulset.yaml"
    "13d-mongo.yaml"
    "13e-mongo-pvc.yaml"
    "13f-collector.yaml"
    "13g-ingresses.yaml"
    "13z-clickstack-chart.yaml"
  ];
}
