# TS6 Manager bootstrap module — web UI for the TeamSpeak 6 server.
#
# Upstream: https://github.com/clusterzx/ts6-manager
# React SPA (nginx) + Express backend (WebQuery client, music bots, flow
# engine) + Go/Pion WebRTC sidecar for video streaming.
#
# Wiring notes:
#   - The frontend image's nginx hardcodes `proxy_pass http://backend:3001`
#     for /api and /ws — so the backend Service MUST be named `backend`
#     in this namespace.
#   - Image tags (frontend/sidecar) are floating; pinned by amd64
#     digest instead. Bump = re-resolve digests from Docker Hub.
#   - The backend image itself is only the artifact seed + runtime deps.
#     Code runs from a git clone (see code-sync initContainer): pushing to
#     the Forgejo fork (Benjamin/ts6-manager-fork) hot-deploys within ~20s.
#     Image builds (docker/ts6-manager/build-in-cluster.sh) are only needed
#     for Dockerfile/dependency changes. Clone creds: ts6-manager-git
#     secret (injected by k8s-secrets-inject from sops forgejo keys).
#   - Backend needs JWT_SECRET (required) + ENCRYPTION_KEY from the
#     injected ts6-manager-secret (sops). Both also declared in
#     modules/services/k8s-secrets-inject.nix.
#   - SQLite DB lives on the ts6-manager-data PVC; one volume, two subPath
#     mounts (DB dir + music library).
#   - Talks to the TS server over the cluster-internal teamspeak-query
#     Service (10080 web / 10022 ssh) — query ports are NOT LAN-exposed.
#   - Public via ingress on ts6.voltrum.co (wildcard *.voltrum.co DNS +
#     cloudflared catch-all route already exist — no DNS changes needed).
{
  pkgs,
  lib,
}: let
  # Backbone nodes are tainted; these workloads explicitly opt in.
  tolerations = "      tolerations:\n        - key: role\n          operator: Equal\n          value: backbone\n          effect: NoSchedule\n        - key: infra\n          operator: Equal\n          value: \"true\"\n          effect: NoSchedule";

  pvc = ''
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ts6-manager-data
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 5Gi
'';

  backend = ''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ts6-manager-backend
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: backend
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: ts6-manager
      app.kubernetes.io/component: backend
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ts6-manager
        app.kubernetes.io/component: backend
    spec:
${tolerations}
      automountServiceAccountToken: false
      # Harbor (10.0.0.56:5000) requires auth for pulls; same convention as
      # edukurs/forgejo/mosaic namespaces (dockerconfigjson pull secret)
      imagePullSecrets:
        - name: harbor-registry
      securityContext:
        # node:20-slim has a uid-1000 `node` user; fsGroup chowns the PVC
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
      initContainers:
        # The pinned upstream image ships yt-dlp 2026.03.03, which YouTube
        # breaks within ~90 days. Deliberately floating download: freshness
        # is the point — yt-dlp is the one artifact that MUST stay current.
        # The zipapp replaces the pip script on PATH (bare `yt-dlp` spawn).
        - name: yt-dlp-update
          image: curlimages/curl:latest@sha256:43366cd60f226c7655181a0f7e85c468a41d182fdd2dc2c1c3b872a2b9d05d7a
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - curl -fsSL --retry 3 -o /out/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp && chmod +x /out/yt-dlp
          volumeMounts:
            - name: yt-dlp-bin
              mountPath: /out
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 200m
              memory: 64Mi
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
        # yt-dlp's YouTube challenge solver (ejs) dropped Node <22 support
        # ('JS runtimes: node-20.20.1 (unsupported)'); deno is its default
        # and recommended runtime. Copy the static binary into the same
        # PATH-override dir as yt-dlp so it lands first on PATH.
        - name: deno-bin
          image: denoland/deno:latest@sha256:869d374bdaddda4fde029c492d7219199b0e821c2c53cca5357b3a6f5b9336fc
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - cp /usr/bin/deno /out/deno && chmod 0755 /out/deno && /out/deno --version
          volumeMounts:
            - name: yt-dlp-bin
              mountPath: /out
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 500m
              memory: 128Mi
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
        # Hot deploy: clone the patched fork into the `src` emptyDir. The
        # main container mounts it at /srv/src (NOT over /app — the image's
        # own /app must stay visible: node_modules, the generated Prisma
        # client and the built @ts6/common dist are gitignored, so they are
        # copied from the image into the clone by the main container's
        # entrypoint). Its git-poll loop resets the working tree to
        # origin/main every 20s, so `git push` to Benjamin/ts6-manager-fork
        # hot-deploys without an image build. Image builds are only needed
        # for Dockerfile/dependency changes.
        - name: code-sync
          # Same digest-pinned alpine/git as the kaniko build job
          image: alpine/git:latest@sha256:52be47b4d5ffd7e65439b4872d498897426c41afa38fde44d6c2f2f3249aaa97
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
              set -e
              URL="http://$GIT_USER:$GIT_TOKEN@forgejo-http.forgejo.svc:3000/Benjamin/ts6-manager-fork.git"
              # Idempotent: a partial clone from a crashed earlier attempt
              # must not wedge the init (emptyDir persists across restarts)
              if [ -d /src/.git ]; then
                echo "[code-sync] existing clone found; fetching"
                git -C /src fetch --depth 50 origin main
                git -C /src reset --hard FETCH_HEAD
              else
                # Clean leftovers of a crashed attempt (contents only — /src
                # itself is the emptyDir mountpoint, removing it is EBUSY)
                rm -rf /src/.git /src/* /src/.[!.]* 2>/dev/null || true
                echo "[code-sync] cloning fork"
                git clone --depth 50 "$URL" /src
              fi
              git -C /src log --oneline -1
              # Main container runs as uid 1000 (tsx only reads source, but
              # git needs to write .git for the fetch loop)
              chown -R 1000:1000 /src
              echo "[code-sync] ready"
          env:
            - name: HOME
              value: /tmp
            - name: GIT_USER
              valueFrom:
                secretKeyRef:
                  name: ts6-manager-git
                  key: username
            - name: GIT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: ts6-manager-git
                  key: token
          volumeMounts:
            - name: src
              mountPath: /src
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
          securityContext:
            runAsNonRoot: false
            runAsUser: 0
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
              # chown -R to uid 1000
              add: ["CHOWN", "FOWNER"]
      containers:
        - name: backend
          # Custom build: adds !playlist chat commands — patch + build script
          # in docker/ts6-manager/ (this repo). Base: upstream backend-dev
          # (queue chat subcommands) + patch. The container RUNS FROM GIT:
          # the code-sync initContainer clones the fork into `src` (seeded
          # with this image's node_modules/generated/dist) and the command
          # below polls + resets to origin/main, restarting via tsx watch.
          # Bump the tag only for Dockerfile/dependency changes.
          image: 10.0.0.56:5000/library/ts6-manager-backend:0.16.2
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              set -e
              SRC=/srv/src
              # Seed gitignored artifacts from the image (init containers run
              # their OWN rootfs, so this can only happen here). Plain cp
              # (no -a) → files owned by uid 1000 so tsc/prisma generate can
              # overwrite them on hot updates. Survives git reset --hard
              # (untracked).
              cp -r /app/node_modules $SRC/node_modules
              cp -r /app/packages/backend/node_modules $SRC/packages/backend/node_modules
              cp -r /app/packages/backend/generated $SRC/packages/backend/generated
              cp -r /app/packages/common/dist $SRC/packages/common/dist
              cd $SRC/packages/backend
              npx prisma db push --skip-generate
              npx prisma db seed || true
              # Hot-deploy poll: every 20s, fetch origin/main and reset the
              # working tree when it moved. tsx watch (below) restarts the
              # server the moment the files change. Seeded artifacts are
              # gitignored → survive reset. NO pnpm here: any pnpm invocation
              # can trigger a dependency re-install (slow + v10 build-script
              # guard); tsc/prisma resolve straight from the seeded
              # node_modules.
              (
                while :; do
                  sleep 20
                  if git -C $SRC fetch -q origin main; then
                    if [ "$(git -C $SRC rev-parse HEAD)" != "$(git -C $SRC rev-parse FETCH_HEAD)" ]; then
                      echo "[hot-deploy] updating to $(git -C $SRC rev-parse --short FETCH_HEAD)"
                      git -C $SRC reset --hard -q FETCH_HEAD
                      ( cd $SRC/packages/common && npx tsc \
                          && cd $SRC/packages/backend \
                          && npx prisma generate \
                          && npx prisma db push --skip-generate ) \
                        || echo "[hot-deploy] post-update steps failed (ts watch still restarts on file changes)"
                    fi
                  fi
                done
              ) &
              exec npx tsx watch src/index.ts
          ports:
            - name: http
              containerPort: 3001
              protocol: TCP
          env:
            # Prepend the initContainer-fetched yt-dlp (zipapp needs the
            # image's /usr/bin/python3, hence PATH override not a bind)
            - name: PATH
              value: /opt/yt-dlp-override:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            - name: HOME
              value: /tmp
            - name: NODE_ENV
              value: production
            - name: PORT
              value: "3001"
            - name: DATABASE_URL
              value: file:/srv/src/packages/backend/data/ts6webui.db
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: ts6-manager-secret
                  key: JWT_SECRET
            - name: ENCRYPTION_KEY
              valueFrom:
                secretKeyRef:
                  name: ts6-manager-secret
                  key: ENCRYPTION_KEY
            - name: FRONTEND_URL
              value: https://ts6.voltrum.co
            - name: MUSIC_DIR
              value: /data/music
            - name: SIDECAR_URL
              value: http://ts6-sidecar:9800
            - name: TS_ALLOW_SELF_SIGNED
              value: "false"
            - name: JWT_ACCESS_EXPIRY
              value: 15m
            - name: JWT_REFRESH_EXPIRY
              value: 7d
          volumeMounts:
            # Git-synced source; /app (image) stays intact so the entrypoint
            # can copy gitignored artifacts out of it. The PVC data mount
            # nests into the clone (kubelet orders mounts by depth).
            - name: src
              mountPath: /srv/src
            - name: yt-dlp-bin
              mountPath: /opt/yt-dlp-override
              readOnly: true
            - name: ytdlp-config
              mountPath: /etc/yt-dlp/config
              subPath: config
              readOnly: true
            # One PVC, two subPath mounts (DB dir + music library)
            - name: data
              mountPath: /srv/src/packages/backend/data
              subPath: data
            - name: data
              mountPath: /data/music
              subPath: music
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: "2"
              memory: 1Gi
          # Entry does prisma db push + seed before listening
          startupProbe:
            tcpSocket:
              port: http
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 36
          readinessProbe:
            tcpSocket:
              port: http
            periodSeconds: 10
            timeoutSeconds: 3
          livenessProbe:
            tcpSocket:
              port: http
            initialDelaySeconds: 60
            periodSeconds: 20
            timeoutSeconds: 3
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
            claimName: ts6-manager-data
        - name: src
          emptyDir: {}
        - name: yt-dlp-bin
          emptyDir: {}
        - name: ytdlp-config
          configMap:
            name: ts6-ytdlp-config
'';

  frontend = ''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ts6-manager-frontend
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ts6-manager
      app.kubernetes.io/component: frontend
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ts6-manager
        app.kubernetes.io/component: frontend
    spec:
${tolerations}
      automountServiceAccountToken: false
      containers:
        - name: frontend
          image: clusterzx/ts6-manager:frontend-dev@sha256:0e97a9e6d999c3693773b84cdb74bb8ab99bcd86d8236ac4d2e5ba1efa832bee
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /
              port: http
            periodSeconds: 10
            timeoutSeconds: 3
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 15
            periodSeconds: 20
            timeoutSeconds: 3
            failureThreshold: 6
'';

  sidecar = ''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ts6-manager-sidecar
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: sidecar
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ts6-manager
      app.kubernetes.io/component: sidecar
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ts6-manager
        app.kubernetes.io/component: sidecar
    spec:
${tolerations}
      automountServiceAccountToken: false
      containers:
        - name: sidecar
          image: clusterzx/ts6-manager:sidecar@sha256:a0e5b40e6e07f18cc8d83576a5353266b91736f817f94746ee8134c9e37ee3cb
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 9800
              protocol: TCP
          env:
            - name: SIDECAR_PORT
              value: "9800"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: "2"
              memory: 1Gi
          readinessProbe:
            tcpSocket:
              port: http
            periodSeconds: 10
            timeoutSeconds: 3
          livenessProbe:
            tcpSocket:
              port: http
            initialDelaySeconds: 15
            periodSeconds: 20
            timeoutSeconds: 3
            failureThreshold: 6
'';

  services = ''
apiVersion: v1
kind: Service
metadata:
  # Name is load-bearing: the frontend image's nginx config proxies
  # /api and /ws to http://backend:3001
  name: backend
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: backend
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: backend
  ports:
    - name: http
      port: 3001
      targetPort: http
      protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: frontend
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: frontend
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: ts6-sidecar
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: sidecar
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: sidecar
  ports:
    - name: http
      port: 9800
      targetPort: http
      protocol: TCP
'';

  # yt-dlp system config: new YouTube extraction needs a JS runtime; only
  # 'deno' is enabled by default and the image has no deno, but it does have
  # node. Upstream bakes this into /root/.config which our uid-1000 runtime
  # can't read — /etc/yt-dlp/config is the user-independent location.
  ytdlpConfigMap = ''
apiVersion: v1
kind: ConfigMap
metadata:
  name: ts6-ytdlp-config
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: ts6-manager
    app.kubernetes.io/component: backend
data:
  config: |
    --js-runtimes node
'';

  ingress = ''
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ts6-manager
  namespace: teamspeak
  labels:
    app.kubernetes.io/name: ts6-manager
  annotations:
    # Cloudflare terminates public TLS; nginx talks HTTP to the pod.
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    # Music uploads (frontend nginx allows 150m)
    nginx.ingress.kubernetes.io/proxy-body-size: "150m"
    # Long-lived WebSockets (/ws)
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
    - host: ts6.voltrum.co
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 80
'';
in {
  chartFiles = {};

  inlineFiles = {
    "27-ts6-manager-pvc.yaml" = pvc;
    "27a-ts6-manager-backend.yaml" = backend;
    "27b-ts6-manager-frontend.yaml" = frontend;
    "27c-ts6-manager-sidecar.yaml" = sidecar;
    "27d-ts6-manager-services.yaml" = services;
    "27e-ts6-manager-ingress.yaml" = ingress;
    "27f-ts6-manager-ytdlp-configmap.yaml" = ytdlpConfigMap;
  };

  order = [
    "27-ts6-manager-pvc.yaml"
    "27a-ts6-manager-backend.yaml"
    "27b-ts6-manager-frontend.yaml"
    "27c-ts6-manager-sidecar.yaml"
    "27d-ts6-manager-services.yaml"
    "27e-ts6-manager-ingress.yaml"
    "27f-ts6-manager-ytdlp-configmap.yaml"
  ];
}
