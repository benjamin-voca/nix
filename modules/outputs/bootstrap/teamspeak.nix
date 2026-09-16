# TeamSpeak 6 server bootstrap module.
#
# Official TS6 server beta (matches the TS6 client) from
# teamspeaksystems/teamspeak6-server. See:
#   https://github.com/teamspeak/teamspeak6-server
#
# Profile:
#   - Pinned image tag 6.0.0-beta12.1 (rebuild bump to upgrade; "latest" is
#     a mutable tag and this repo pins versions everywhere else)
#   - SQLite database inside the PVC — TS6 supports MariaDB but a single
#     voice server does not justify a CNPG cluster
#   - Beta license: 32 slots, auto-renewed by upstream every 2 months
#     (TS3 licenses are NOT compatible and there is no TS3 -> TS6 migration)
#   - Exposed as a MetalLB LoadBalancer on 192.168.1.246 (LAN VIP, free in
#     the 192.168.1.240-250 pool; .240 ingress, .245 parked minecraft).
#     Voice is UDP 9987 so Cloudflare tunnel/ingress is not an option.
#   - Only voice + file transfer ports are published. Web query (10080) and
#     SSH query (10022) stay disabled, matching upstream's compose example.
#
# First-boot admin:
#   The ServerAdmin privilege key is printed to the container log on the
#   first start only. Grab it with:
#     kubectl -n teamspeak logs deploy/teamspeak | grep -i "privilege key"
#   and redeem it in the TS6 client (Permissions > Privilege Keys).
#
# NOTE on file transfer: the server advertises its filetransfer port to
# clients, so the external (Service) port must equal the container port
# (30033 -> 30033). A MetalLB LB with identical ports satisfies this.
{
  pkgs,
  lib,
}: let
  # Backbone nodes are tainted; this workload explicitly opts in.
  tolerations = "      tolerations:\n        - key: role\n          operator: Equal\n          value: backbone\n          effect: NoSchedule\n        - key: infra\n          operator: Equal\n          value: \"true\"\n          effect: NoSchedule";

  namespace = ''
apiVersion: v1
kind: Namespace
metadata:
  name: teamspeak
  labels:
    app.kubernetes.io/name: teamspeak
'';

  pvc = ''
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: teamspeak-data
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: teamspeak
    app.kubernetes.io/component: data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 5Gi
'';

  deployment = ''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: teamspeak
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: teamspeak
spec:
  replicas: 1
  # RWO PVC -> old pod must die before the new one mounts the volume
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: teamspeak
  template:
    metadata:
      labels:
        app.kubernetes.io/name: teamspeak
    spec:
${tolerations}
      automountServiceAccountToken: false
      securityContext:
        # Image USER is teamspeak:teamspeak (non-root); pin uid/gid 1000 so
        # the kubelet fsGroup chown of the PVC matches the runtime user.
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
      containers:
        - name: teamspeak
          image: teamspeaksystems/teamspeak6-server:6.0.0-beta12.1
          imagePullPolicy: IfNotPresent
          ports:
            - name: voice
              containerPort: 9987
              protocol: UDP
            - name: filetransfer
              containerPort: 30033
              protocol: TCP
          env:
            - name: TSSERVER_LICENSE_ACCEPTED
              value: accept
          volumeMounts:
            - name: data
              mountPath: /var/tsserver
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: "1"
              memory: 512Mi
          # Voice port is UDP (no tcpSocket probe possible); filetransfer is
          # a plain TCP listener that only comes up once the server is ready.
          startupProbe:
            tcpSocket:
              port: filetransfer
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 12
          readinessProbe:
            tcpSocket:
              port: filetransfer
            periodSeconds: 10
            timeoutSeconds: 3
          livenessProbe:
            tcpSocket:
              port: filetransfer
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 3
            failureThreshold: 6
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: teamspeak-data
'';

  service = ''
apiVersion: v1
kind: Service
metadata:
  name: teamspeak
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: teamspeak
spec:
  # LAN exposure via MetalLB (pool 192.168.1.240-250); .246 is free.
  # Voice is UDP so it cannot go through the nginx ingress / Cloudflare.
  type: LoadBalancer
  loadBalancerIP: 192.168.1.246
  selector:
    app.kubernetes.io/name: teamspeak
  ports:
    - name: voice
      port: 9987
      targetPort: voice
      protocol: UDP
    - name: filetransfer
      port: 30033
      targetPort: filetransfer
      protocol: TCP
'';
in {
  chartFiles = {};

  inlineFiles = {
    "26-teamspeak-namespace.yaml" = namespace;
    "26a-teamspeak-pvc.yaml" = pvc;
    "26b-teamspeak-deployment.yaml" = deployment;
    "26c-teamspeak-service.yaml" = service;
  };

  order = [
    "26-teamspeak-namespace.yaml"
    "26a-teamspeak-pvc.yaml"
    "26b-teamspeak-deployment.yaml"
    "26c-teamspeak-service.yaml"
  ];
}
