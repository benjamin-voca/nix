# Clustta Studio self-hosted creative project server.
#
# Private mode is intentional here: no Clustta Studio API key was provided,
# so the server uses its local user database and has no outbound auth
# dependency. The three volumes mirror Clustta's documented backup units:
# server state/users, project metadata/chunks, and Deflated blobs.
{
  pkgs,
  lib,
}: let
  d = import ../../../lib/domain.nix;

  # Backbone nodes are tainted; this workload explicitly opts in.
  tolerations = "      tolerations:\n        - key: role\n          operator: Equal\n          value: backbone\n          effect: NoSchedule\n        - key: infra\n          operator: Equal\n          value: \"true\"\n          effect: NoSchedule";

  namespace = ''
apiVersion: v1
kind: Namespace
metadata:
  name: clustta
  labels:
    app.kubernetes.io/name: clustta
'';

  pvcs = ''
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: clustta-data
  namespace: clustta
  labels:
    app.kubernetes.io/name: clustta
    app.kubernetes.io/component: data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: clustta-projects
  namespace: clustta
  labels:
    app.kubernetes.io/name: clustta
    app.kubernetes.io/component: projects
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 50Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: clustta-storage
  namespace: clustta
  labels:
    app.kubernetes.io/name: clustta
    app.kubernetes.io/component: storage
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 100Gi
'';

  deployment = ''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clustta
  namespace: clustta
  labels:
    app.kubernetes.io/name: clustta
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: clustta
  template:
    metadata:
      labels:
        app.kubernetes.io/name: clustta
    spec:
${tolerations}
      automountServiceAccountToken: false
      securityContext:
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
      containers:
        - name: clustta
          image: eaxum/clustta:0.4.39
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 7774
              protocol: TCP
          env:
            # Explicitly set these because Kubernetes otherwise injects a
            # CLUSTTA_PORT service variable containing tcp://<cluster-ip>:7774.
            - name: CLUSTTA_HOST
              value: 0.0.0.0
            - name: CLUSTTA_PORT
              value: "7774"
            - name: DATA_DIR
              value: /var/data
            - name: PROJECTS_DIR
              value: /var/projects
            - name: STORAGE_DIR
              value: /var/storage
            - name: STUDIO_USERS_DB
              value: /var/data/studio_users.db
            - name: SESSION_DB
              value: /var/data/sessions.db
            - name: PRIVATE
              value: "true"
          volumeMounts:
            - name: data
              mountPath: /var/data
            - name: projects
              mountPath: /var/projects
            - name: storage
              mountPath: /var/storage
          resources:
            requests:
              cpu: 25m
              memory: 256Mi
            limits:
              cpu: "2"
              memory: 2Gi
          startupProbe:
            httpGet:
              path: /ping
              port: http
            periodSeconds: 5
            timeoutSeconds: 5
            failureThreshold: 60
          readinessProbe:
            httpGet:
              path: /ping
              port: http
            periodSeconds: 10
            timeoutSeconds: 5
          livenessProbe:
            httpGet:
              path: /ping
              port: http
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 6
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: clustta-data
        - name: projects
          persistentVolumeClaim:
            claimName: clustta-projects
        - name: storage
          persistentVolumeClaim:
            claimName: clustta-storage
'';

  service = ''
apiVersion: v1
kind: Service
metadata:
  name: clustta
  namespace: clustta
  labels:
    app.kubernetes.io/name: clustta
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: clustta
  ports:
    - name: http
      port: 7774
      targetPort: http
      protocol: TCP
'';

  ingress = ''
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: clustta
  namespace: clustta
  labels:
    app.kubernetes.io/name: clustta
  annotations:
    # Cloudflare terminates public TLS; nginx talks HTTP to the pod.
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
    - host: ${d.host "clustta"}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: clustta
                port:
                  number: 7774
'';
in {
  chartFiles = {};

  inlineFiles = {
    "24-clustta-namespace.yaml" = namespace;
    "24a-clustta-pvcs.yaml" = pvcs;
    "24b-clustta-deployment.yaml" = deployment;
    "24c-clustta-service.yaml" = service;
    "24d-clustta-ingress.yaml" = ingress;
  };

  order = [
    "24-clustta-namespace.yaml"
    "24a-clustta-pvcs.yaml"
    "24b-clustta-deployment.yaml"
    "24c-clustta-service.yaml"
    "24d-clustta-ingress.yaml"
  ];
}
