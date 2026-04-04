{
  description = "QuadNix NixOS Configuration";

  nixConfig = {
    extra-substituters = [
      "https://nixhelm.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    nixhelm.url = "github:farcaller/nixhelm";
    nix-kube-generators.url = "github:farcaller/nix-kube-generators";
    haumea.url = "github:nix-community/haumea";
    haumea.inputs.nixpkgs.follows = "nixpkgs";
  };


  outputs = inputs:
    let
      lib = inputs.nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = lib.genAttrs systems;
      helmLibFor = system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          kubelib = inputs.nix-kube-generators.lib { inherit pkgs; };
          localCharts = inputs.haumea.lib.load {
            src = ./charts;
            transformer = inputs.haumea.lib.transformers.liftDefault;
          };
          localChartsDerivations = builtins.mapAttrs (repo: charts:
            builtins.mapAttrs (name: chart:
              kubelib.downloadHelmChart {
                repo = chart.repo;
                chart = chart.chart;
                version = chart.version;
              }
            ) charts
          ) localCharts;
          helmLib = import ./lib/helm {
            inherit (inputs) nixhelm nix-kube-generators;
            inherit pkgs system;
          };
        in
        helmLib // { chartsDerivations = localChartsDerivations; };
      argocdChartFor = system:
        let
          helmLib = helmLibFor system;
        in
          helmLib.buildChart {
            name = "argocd";
            chart = helmLib.charts.argoproj.argo-cd;
            namespace = "argocd";
            values = {
              global = {
                domain = "argocd.quadtech.dev";
              };

              configs = {
                cm = {
                  "server.insecure" = true;
                  url = "https://argocd.quadtech.dev";
                };
                cmData = {
                  "server.insecure" = "true";
                };
                params = {
                  "server.insecure" = true;
                };
                secret = {
                  argocdServerAdminPassword = "PLACEHOLDER";
                };
              };

              server = {
                replicas = 1;
                service = {
                  type = "ClusterIP";
                };
              };

              redis = {
                enabled = true;
              };

              redis-ha = {
                enabled = false;
              };

              controller = {
                replicas = 1;
              };

              repoServer = {
                replicas = 1;
              };

              applicationSet = {
                enabled = true;
              };

              notifications = {
                enabled = true;
              };

              global.image.tag = "v2.9.3";

              server.ingress = {
                enabled = true;
                annotations = {
                  "nginx.ingress.kubernetes.io/ssl-redirect" = "false";
                  "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
                };
                ingressClassName = "nginx";
                hosts = ["argocd.quadtech.dev"];
                tls = true;
              };
            };
          };
      flakeOutputs = {
        helmLib = forAllSystems (system: helmLibFor system);
        argocdChart = forAllSystems (system: argocdChartFor system);
        packages = forAllSystems (system: {
          inherit (inputs.nixhelm.packages.${system}) helmupdater;
          bootstrap = argocdBootstrap.${system};
          boostrap = argocdBootstrap.${system};
        });
        apps = forAllSystems (system: {
          inherit (inputs.nixhelm.apps.${system}) helmupdater;
        });
        chartsMetadata = inputs.haumea.lib.load {
          src = ./charts;
          transformer = inputs.haumea.lib.transformers.liftDefault;
        };
        chartsDerivations = forAllSystems (system: helmLibFor system).chartsDerivations;
      };

      # Bootstrap that creates ArgoCD Applications (declarative GitOps)
      argocdBootstrap = forAllSystems (system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
        pkgs.runCommand "argocd-bootstrap"
          {
            inherit system;
            preferLocalBuild = true;
          }
          ''
          mkdir -p $out
          cat > $out/bootstrap.yaml << 'BOOTSTRAP_EOF'
          # ArgoCD Bootstrap - Namespaces
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: argocd
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: metallb
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: ingress-nginx
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: harbor
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: erpnext
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: nfs-rwx
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: quadpacient

          # MetalLB CRDs
          ---
          apiVersion: metallb.io/v1beta1
          kind: IPAddressPool
          metadata:
            name: default
            namespace: metallb
          spec:
            addresses:
            - 192.168.1.240-192.168.1.250
            autoAssign: true
          ---
          apiVersion: metallb.io/v1beta1
          kind: L2Advertisement
          metadata:
            name: default
            namespace: metallb
          spec:
            ipAddressPools:
            - default

          # ArgoCD Application - ArgoCD itself
          ---
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: argocd
            namespace: argocd
          spec:
            project: default
            source:
              chart: argo-cd
              repoURL: https://argoproj.github.io/argo-helm
              targetRevision: 9.3.5
              helm:
                parameters:
                - name: global.domain
                  value: argocd.quadtech.dev
                - name: server.insecure
                  value: "true"
                - name: server.forceHttp
                  value: "true"
                - name: server.service.type
                  value: ClusterIP
                - name: server.ingress.enabled
                  value: "true"
                - name: server.ingress.ingressClassName
                  value: nginx
                - name: server.ingress.annotations nginx\.ingress\.kubernetes\.io/ssl-redirect
                  value: "false"
                - name: server.ingress.annotations nginx\.ingress\.kubernetes\.io/backend-protocol
                  value: HTTP
                - name: server.ingress.hosts[0]
                  value: argocd.quadtech.dev
                - name: server.ingress.tls
                  value: "true"
            destination:
              server: https://kubernetes.default.svc
              namespace: argocd
            syncPolicy:
              automated:
                prune: true
                selfHeal: true

          # ArgoCD Application - MetalLB
          ---
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: metallb
            namespace: argocd
          spec:
            ignoreDifferences:
            - group: apiextensions.k8s.io
              kind: CustomResourceDefinition
              jsonPointers:
              - /spec
            project: default
            source:
              chart: metallb
              repoURL: https://metallb.github.io/metallb
              targetRevision: 0.14.8
              helm:
                parameters:
                - name: controller.config.addressPools.default.addresses
                  value: "[192.168.1.240-192.168.1.250]"
                - name: controller.config.addressPools.default.autoAssign
                  value: "true"
            destination:
              server: https://kubernetes.default.svc
              namespace: metallb
            syncPolicy:
              automated:
                prune: true
                selfHeal: true

          # ArgoCD Application - Ingress-Nginx
          ---
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: ingress-nginx
            namespace: argocd
          spec:
            project: default
            source:
              chart: ingress-nginx
              repoURL: https://kubernetes.github.io/ingress-nginx
              targetRevision: 4.14.1
              helm:
                parameters:
                - name: controller.service.type
                  value: LoadBalancer
                - name: controller.publishService.enabled
                  value: "true"
            destination:
              server: https://kubernetes.default.svc
              namespace: ingress-nginx
            syncPolicy:
              automated:
                prune: true
                selfHeal: true

          # ArgoCD Application - Harbor
          ---
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: harbor
            namespace: argocd
          spec:
            ignoreDifferences:
            - group: networking.k8s.io
              kind: Ingress
              jsonPointers:
              - /metadata/annotations
            project: default
            source:
              chart: harbor
              repoURL: https://helm.goharbor.io
              targetRevision: 1.18.1
              helm:
                parameters:
                - name: expose.ingress.annotations nginx\.ingress\.kubernetes\.io/ssl-redirect
                  value: "false"
                - name: expose.ingress.annotations ingress\.kubernetes\.io/ssl-redirect
                  value: "false"
                - name: expose.ingress.annotations nginx\.ingress\.kubernetes\.io/proxy-body-size
                  value: "0"
                - name: expose.ingress.annotations ingress\.kubernetes\.io/proxy-body-size
                  value: "0"
                - name: externalURL
                  value: https://harbor.quadtech.dev
                - name: expose.ingress.hosts.core
                  value: harbor.quadtech.dev
                - name: persistence.enabled
                  value: "true"
                - name: persistence.resourcePolicy
                  value: keep
                - name: persistence.persistentVolumeClaim.registry.existingClaim
                  value: harbor-registry-ceph
                - name: persistence.persistentVolumeClaim.jobservice.jobLog.existingClaim
                  value: harbor-jobservice-ceph
                - name: persistence.persistentVolumeClaim.database.existingClaim
                  value: harbor-database-ceph
                - name: persistence.persistentVolumeClaim.redis.existingClaim
                  value: harbor-redis-ceph
                - name: persistence.persistentVolumeClaim.trivy.existingClaim
                  value: harbor-trivy-ceph
            destination:
              server: https://kubernetes.default.svc
              namespace: harbor
            syncPolicy:
              automated:
                prune: true
                selfHeal: true

          # ERPNext PVC
          ---
          apiVersion: v1
          kind: PersistentVolumeClaim
          metadata:
            name: erpnext-databases
            namespace: erpnext
          spec:
            accessModes:
              - ReadWriteOnce
            storageClassName: ceph-block
            resources:
              requests:
                storage: 20Gi

          # CephFS for ERPNext shared RWX data
          ---
          apiVersion: ceph.rook.io/v1
          kind: CephFilesystemSubVolumeGroup
          metadata:
            name: ceph-filesystem-csi
            namespace: rook-ceph
          spec:
            name: csi
            filesystemName: ceph-filesystem
            pinning:
              distributed: 1

          ---
          apiVersion: ceph.rook.io/v1
          kind: CephFilesystem
          metadata:
            name: ceph-filesystem
            namespace: rook-ceph
          spec:
            metadataPool:
              replicated:
                size: 1
            dataPools:
              - name: data0
                failureDomain: host
                replicated:
                  size: 1
            metadataServer:
              activeCount: 1
              activeStandby: true

          ---
          apiVersion: storage.k8s.io/v1
          kind: StorageClass
          metadata:
            name: ceph-filesystem-csi
          provisioner: rook-ceph.cephfs.csi.ceph.com
          allowVolumeExpansion: true
          reclaimPolicy: Delete
          volumeBindingMode: Immediate
          parameters:
            clusterID: rook-ceph
            fsName: ceph-filesystem
            pool: ceph-filesystem-data0
            subvolumeGroup: csi
            csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
            csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
            csi.storage.k8s.io/controller-expand-secret-name: rook-csi-cephfs-provisioner
            csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
            csi.storage.k8s.io/controller-publish-secret-name: rook-csi-cephfs-provisioner
            csi.storage.k8s.io/controller-publish-secret-namespace: rook-ceph
            csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
            csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
            csi.storage.k8s.io/fstype: ext4

          # ERPNext shared sites PVC on CephFS (migration target)
          ---
          apiVersion: v1
          kind: PersistentVolumeClaim
          metadata:
            name: erpnext-sites-rwx-ceph-v2
            namespace: erpnext
          spec:
            accessModes:
              - ReadWriteMany
            storageClassName: ceph-filesystem-csi
            resources:
              requests:
                storage: 20Gi

          # Host-backed PV for in-cluster NFS storage
          ---
          apiVersion: v1
          kind: PersistentVolume
          metadata:
            name: nfs-rwx-data
          spec:
            capacity:
              storage: 50Gi
            accessModes:
              - ReadWriteOnce
            persistentVolumeReclaimPolicy: Retain
            storageClassName: ""
            hostPath:
              path: /var/lib/quadnix/nfs-rwx
              type: DirectoryOrCreate

          ---
          apiVersion: v1
          kind: PersistentVolumeClaim
          metadata:
            name: nfs-rwx-data
            namespace: nfs-rwx
          spec:
            accessModes:
              - ReadWriteOnce
            storageClassName: ""
            volumeName: nfs-rwx-data
            resources:
              requests:
                storage: 50Gi

          # ArgoCD Application - In-cluster NFS provisioner
          ---
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: nfs-rwx
            namespace: argocd
          spec:
            project: default
            source:
              chart: nfs-server-provisioner
              repoURL: https://kubernetes-sigs.github.io/nfs-ganesha-server-and-external-provisioner
              targetRevision: 1.8.0
              helm:
                releaseName: nfs-rwx-hostpath
                values: |
                  persistence:
                    enabled: true
                    existingClaim: nfs-rwx-data

                  storageClass:
                    create: true
                    defaultClass: false
                    name: nfs-rwx-v2
                    provisionerName: quadtech.dev/nfs-rwx-v2
                    mountOptions:
                      - vers=4.1

                  service:
                    type: ClusterIP
            destination:
              server: https://kubernetes.default.svc
              namespace: nfs-rwx
            syncPolicy:
              automated:
                prune: true
                selfHeal: true

          # ERPNext bootstrap Helpdesk job (declarative one-shot)
          ---
          apiVersion: batch/v1
          kind: Job
          metadata:
            name: erpnext-bootstrap-helpdesk-v20
            namespace: erpnext
          spec:
            backoffLimit: 2
            activeDeadlineSeconds: 1800
            template:
              spec:
                restartPolicy: Never
                containers:
                  - name: bootstrap-helpdesk
                    image: frappe/erpnext:v16.5.0
                    imagePullPolicy: IfNotPresent
                    command:
                      - /bin/bash
                      - -lc
                    args:
                      - |
                        set -euxo pipefail

                        SITE_NAME="helpdesk.quadtech.dev"
                        APPS_DIR="/home/frappe/frappe-bench/sites/apps"

                        export PYTHONPATH="/home/frappe/frappe-bench/sites/vendor:/home/frappe/frappe-bench/sites/apps/telephony:/home/frappe/frappe-bench/sites/apps/helpdesk''${PYTHONPATH:+:$PYTHONPATH}"

                        for i in $(seq 1 60); do if [ -f /home/frappe/frappe-bench/sites/common_site_config.json ]; then break; fi; echo "Waiting for common_site_config.json ($i/60)"; sleep 5; done
                        [ -f /home/frappe/frappe-bench/sites/common_site_config.json ]

                        for i in $(seq 1 60); do if (echo > /dev/tcp/"$DB_HOST"/"$DB_PORT") >/dev/null 2>&1; then break; fi; echo "Waiting for MariaDB TCP ($i/60)"; sleep 5; done
                        (echo > /dev/tcp/"$DB_HOST"/"$DB_PORT") >/dev/null 2>&1

                        sync_repo() {
                          name="$1"
                          url="$2"
                          branch="$3"
                          target="$APPS_DIR/$name"

                          rm -rf "$target"
                          git clone --depth 1 --branch "$branch" "$url" "$target"
                        }

                        mkdir -p "$APPS_DIR"
                        mkdir -p /home/frappe/frappe-bench/sites/vendor
                        sync_repo telephony https://github.com/frappe/telephony.git develop
                        sync_repo helpdesk https://github.com/frappe/helpdesk.git main
                        /home/frappe/frappe-bench/env/bin/pip install --no-cache-dir twilio textblob
                        printf '%s\n' frappe erpnext telephony helpdesk > /home/frappe/frappe-bench/sites/apps.txt

                        for i in $(seq 1 60); do if mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" --silent >/dev/null 2>&1; then break; fi; echo "Waiting for MariaDB admin auth ($i/60)"; sleep 5; done
                        mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" --silent >/dev/null 2>&1

                        SITE_CONFIG="/home/frappe/frappe-bench/sites/$SITE_NAME/site_config.json"

                        if [ ! -f "$SITE_CONFIG" ]; then
                          bench new-site "$SITE_NAME" \
                            --no-mariadb-socket \
                            --db-type=mariadb \
                            --db-host="$DB_HOST" \
                            --db-port="$DB_PORT" \
                            --admin-password="$ERPNEXT_ADMIN_PASSWORD" \
                            --mariadb-root-username="$DB_ADMIN_USER" \
                            --mariadb-root-password="$DB_ADMIN_PASSWORD" \
                            --mariadb-user-host-login-scope=% \
                            --force
                        fi

                        export PYTHONPATH="/home/frappe/frappe-bench/sites/apps/telephony:/home/frappe/frappe-bench/sites/apps/helpdesk''${PYTHONPATH:+:$PYTHONPATH}"

                        if ! bench --site "$SITE_NAME" list-apps | grep -qx telephony; then
                          bench --site "$SITE_NAME" install-app --force telephony
                        fi
                        if ! bench --site "$SITE_NAME" list-apps | grep -qx helpdesk; then
                          bench --site "$SITE_NAME" install-app --force helpdesk
                        fi

                        bench --site "$SITE_NAME" migrate
                    env:
                      - name: DB_HOST
                        value: erpnext-mariadb-subchart
                      - name: DB_PORT
                        value: "3306"
                      - name: DB_ADMIN_USER
                        value: root
                      - name: DB_ADMIN_PASSWORD
                        valueFrom:
                          secretKeyRef:
                            name: erpnext-mariadb-auth
                            key: mariadb-root-password
                      - name: ERPNEXT_ADMIN_PASSWORD
                        valueFrom:
                          secretKeyRef:
                            name: erpnext-admin
                            key: password
                    volumeMounts:
                      - name: sites-dir
                        mountPath: /home/frappe/frappe-bench/sites
                      - name: logs
                        mountPath: /home/frappe/frappe-bench/logs
                volumes:
                  - name: sites-dir
                    persistentVolumeClaim:
                      claimName: erpnext-sites-rwx-ceph-v2
                  - name: logs
                    emptyDir: {}

          # ArgoCD Application - ERPNext
          ---
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: erpnext
            namespace: argocd
          spec:
            ignoreDifferences:
            - group: networking.k8s.io
              kind: Ingress
              jsonPointers:
              - /metadata/annotations
            project: default
            source:
              chart: erpnext
              repoURL: https://helm.erpnext.com
              targetRevision: 8.0.22
              helm:
                values: |
                  ingress:
                    enabled: true
                    className: nginx
                    annotations:
                      nginx.ingress.kubernetes.io/ssl-redirect: "false"
                      nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
                      nginx.ingress.kubernetes.io/backend-protocol: HTTP
                      nginx.ingress.kubernetes.io/proxy-ssl-redirect: "false"
                    hosts:
                      - host: helpdesk.quadtech.dev
                        paths:
                          - path: /
                            pathType: Prefix
                    tls: []

                  image:
                    repository: frappe/erpnext
                    tag: v16.5.0

                  nginx:
                    config: |
                      upstream backend-server {
                        server erpnext-gunicorn:8000 fail_timeout=0;
                      }

                      upstream socketio-server {
                        server erpnext-socketio:9000 fail_timeout=0;
                      }

                      server {
                        listen 8080;
                        server_name $host;
                        root /home/frappe/frappe-bench/sites;

                        proxy_buffer_size 128k;
                        proxy_buffers 4 256k;
                        proxy_busy_buffers_size 256k;

                        add_header X-Frame-Options "SAMEORIGIN";
                        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
                        add_header X-Content-Type-Options nosniff;
                        add_header X-XSS-Protection "1; mode=block";
                        add_header Referrer-Policy "same-origin, strict-origin-when-cross-origin";

                        set_real_ip_from 127.0.0.1;
                        real_ip_header X-Forwarded-For;
                        real_ip_recursive off;

                        location /assets/helpdesk/ {
                          alias /home/frappe/frappe-bench/sites/apps/helpdesk/helpdesk/public/;
                        }

                        location /assets/telephony/ {
                          alias /home/frappe/frappe-bench/sites/apps/telephony/telephony/public/;
                        }

                        location /assets {
                          try_files $uri =404;
                        }

                        location ~ ^/protected/(.*) {
                          internal;
                          try_files /$host/$1 =404;
                        }

                        location /socket.io {
                          proxy_http_version 1.1;
                          proxy_set_header Upgrade $http_upgrade;
                          proxy_set_header Connection "upgrade";
                          proxy_set_header X-Frappe-Site-Name $host;
                          proxy_set_header Origin $scheme://$http_host;
                          proxy_set_header Host $host;

                          proxy_pass http://socketio-server;
                        }

                        location / {
                          rewrite ^(.+)/$ $1 permanent;
                          rewrite ^(.+)/index\.html$ $1 permanent;
                          rewrite ^(.+)\.html$ $1 permanent;

                          location ~ ^/files/.*.(htm|html|svg|xml) {
                            add_header Content-disposition "attachment";
                            try_files /$host/public/$uri @webserver;
                          }

                          try_files /$host/public/$uri @webserver;
                        }

                        location @webserver {
                          proxy_http_version 1.1;
                          proxy_set_header X-Forwarded-For $remote_addr;
                          proxy_set_header X-Forwarded-Proto $scheme;
                          proxy_set_header X-Frappe-Site-Name $host;
                          proxy_set_header Host $host;
                          proxy_set_header X-Use-X-Accel-Redirect True;
                          proxy_read_timeout 120;
                          proxy_redirect off;

                          proxy_pass  http://backend-server;
                        }

                        sendfile on;
                        keepalive_timeout 15;
                        client_max_body_size 50m;
                        client_body_buffer_size 16K;
                        client_header_buffer_size 1k;

                        gzip on;
                        gzip_http_version 1.1;
                        gzip_comp_level 5;
                        gzip_min_length 256;
                        gzip_proxied any;
                        gzip_vary on;
                        gzip_types
                          application/atom+xml
                          application/javascript
                          application/json
                          application/rss+xml
                          application/vnd.ms-fontobject
                          application/x-font-ttf
                          application/font-woff
                          application/x-web-app-manifest+json
                          application/xhtml+xml
                          application/xml
                          font/opentype
                          image/svg+xml
                          image/x-icon
                          text/css
                          text/plain
                          text/x-component;
                      }

                  persistence:
                    enabled: true
                    worker:
                      enabled: true
                      existingClaim: erpnext-sites-rwx-ceph-v2
                    sites:
                      enabled: true
                      existingClaim: erpnext-sites-rwx-ceph-v2

                  mariadb:
                    enabled: true

                  mariadb-subchart:
                    auth:
                      existingSecret: erpnext-mariadb-auth
                      database: frappe_bootstrap
                      username: frappe_admin
                    initdbScripts:
                      00-create-frappe-admin.sql: |
                        GRANT ALL PRIVILEGES ON *.* TO 'frappe_admin'@'%' WITH GRANT OPTION;
                        FLUSH PRIVILEGES;
                    primary:
                      persistence:
                        enabled: true
                        existingClaim: erpnext-databases
                      livenessProbe:
                        enabled: false
                      readinessProbe:
                        enabled: false
                      customReadinessProbe:
                        initialDelaySeconds: 30
                        periodSeconds: 10
                        timeoutSeconds: 5
                        failureThreshold: 6
                        successThreshold: 1
                        exec:
                          command:
                            - /bin/bash
                            - -ec
                            - >
                              : > /dev/tcp/127.0.0.1/3306
                      customLivenessProbe:
                        initialDelaySeconds: 120
                        periodSeconds: 10
                        timeoutSeconds: 5
                        failureThreshold: 6
                        successThreshold: 1
                        exec:
                          command:
                            - /bin/bash
                            - -ec
                            - >
                              : > /dev/tcp/127.0.0.1/3306

                  jobs:
                    configure:
                      args:
                        - >
                          mkdir -p sites/apps;
                          ls -1 sites/apps > sites/apps.txt;
                          [[ -f sites/common_site_config.json ]] || echo "{}" > sites/common_site_config.json;
                          bench set-config -gp db_port $DB_PORT;
                          bench set-config -g db_host $DB_HOST;
                          bench set-config -g redis_cache $REDIS_CACHE;
                          bench set-config -g redis_queue $REDIS_QUEUE;
                          bench set-config -g redis_socketio $REDIS_QUEUE;
                          bench set-config -gp socketio_port $SOCKETIO_PORT;
                    createSite:
                      enabled: false
                    custom:
                      enabled: false
                      jobName: erpnext-bootstrap-helpdesk-v20
                      restartPolicy: OnFailure
                      containers:
                        - name: bootstrap-helpdesk
                          image: frappe/erpnext:v16.5.0
                          imagePullPolicy: IfNotPresent
                          command:
                            - /bin/bash
                            - -lc
                          args:
                            - |
                              set -euo pipefail

                              export SITE_NAME="helpdesk.quadtech.dev"
                              export PYTHONPATH="/home/frappe/frappe-bench/sites/vendor:/home/frappe/frappe-bench/sites/apps/telephony:/home/frappe/frappe-bench/sites/apps/helpdesk''${PYTHONPATH:+:$PYTHONPATH}"
                              site_config="/home/frappe/frappe-bench/sites/$SITE_NAME/site_config.json"

                              until [ -f /home/frappe/frappe-bench/sites/common_site_config.json ]; do
                                echo "Waiting for common_site_config.json"
                                sleep 5
                              done

                              until (echo > /dev/tcp/"$DB_HOST"/"$DB_PORT") >/dev/null 2>&1; do
                                echo "Waiting for MariaDB"
                                sleep 5
                              done

                              sync_repo() {
                                name="$1"
                                url="$2"
                                branch="$3"
                                target="/home/frappe/frappe-bench/sites/apps/$name"

                                if [ -d "$target/.git" ]; then
                                  if git -C "$target" remote get-url origin >/dev/null 2>&1 && git -C "$target" fetch --depth 1 origin "$branch"; then
                                    git -C "$target" checkout -B "$branch" "origin/$branch"
                                    git -C "$target" reset --hard "origin/$branch"
                                    return
                                  fi
                                  echo "Re-cloning $name checkout"
                                fi

                                rm -rf "$target"
                                git clone --depth 1 --branch "$branch" "$url" "$target"
                              }

                              mkdir -p /home/frappe/frappe-bench/sites/apps
                              mkdir -p /home/frappe/frappe-bench/sites/vendor
                              sync_repo telephony https://github.com/frappe/telephony.git develop
                              sync_repo helpdesk https://github.com/frappe/helpdesk.git main
                              /home/frappe/frappe-bench/env/bin/pip install --no-cache-dir twilio textblob
                              printf '%s\n' frappe erpnext telephony helpdesk > /home/frappe/frappe-bench/sites/apps.txt

                              wait_for_db_admin() {
                                until mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" --silent >/dev/null 2>&1; do
                                  echo "Waiting for MariaDB admin access"
                                  sleep 5
                                done
                              }

                              wait_for_db_admin

                              mysql -h "$DB_HOST" -P "$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" <<SQL
                              DROP DATABASE IF EXISTS helpdesk_db;
                              DROP USER IF EXISTS 'helpdesk_db'@'%';
                              FLUSH PRIVILEGES;
                              SQL

                              rm -rf "/home/frappe/frappe-bench/sites/$SITE_NAME"

                              bench new-site "$SITE_NAME" \
                                --no-mariadb-socket \
                                --db-type=mariadb \
                                --db-host="$DB_HOST" \
                                --db-port="$DB_PORT" \
                                --admin-password="$ERPNEXT_ADMIN_PASSWORD" \
                                --mariadb-root-username="$DB_ADMIN_USER" \
                                --mariadb-root-password="$DB_ADMIN_PASSWORD" \
                                --mariadb-user-host-login-scope=% \
                                --force

                              export PYTHONPATH="/home/frappe/frappe-bench/sites/apps/telephony:/home/frappe/frappe-bench/sites/apps/helpdesk:$PYTHONPATH"

                              if ! bench --site "$SITE_NAME" list-apps | grep -qx telephony; then
                                bench --site "$SITE_NAME" install-app --force telephony
                              fi
                              if ! bench --site "$SITE_NAME" list-apps | grep -qx helpdesk; then
                                bench --site "$SITE_NAME" install-app --force helpdesk
                              fi

                              bench --site "$SITE_NAME" migrate
                          env:
                            - name: DB_HOST
                              value: erpnext-mariadb-subchart
                            - name: DB_PORT
                              value: "3306"
                            - name: DB_ADMIN_USER
                              value: root
                            - name: DB_ADMIN_PASSWORD
                              valueFrom:
                                secretKeyRef:
                                  name: erpnext-mariadb-auth
                                  key: mariadb-root-password
                            - name: ERPNEXT_ADMIN_PASSWORD
                              valueFrom:
                                secretKeyRef:
                                  name: erpnext-admin
                                  key: password
                          volumeMounts:
                            - name: sites-dir
                              mountPath: /home/frappe/frappe-bench/sites
                            - name: logs
                              mountPath: /home/frappe/frappe-bench/logs
                      volumes:
                        - name: sites-dir
                          persistentVolumeClaim:
                            claimName: erpnext-sites-rwx-ceph-v2
                        - name: logs
                          emptyDir: {}

                  worker:
                    gunicorn:
                      envVars: &helpdeskEnv
                        - name: PYTHONPATH
                          value: &helpdeskPythonPath /home/frappe/frappe-bench/sites/vendor:/home/frappe/frappe-bench/sites/apps/telephony:/home/frappe/frappe-bench/sites/apps/helpdesk
                      initContainers: &waitForHelpdeskApps
                        - name: wait-for-helpdesk-apps
                          image: frappe/erpnext:v16.5.0
                          imagePullPolicy: IfNotPresent
                          command:
                            - /bin/bash
                            - -lc
                          args:
                            - |
                              set -euo pipefail
                              until [ -f /home/frappe/frappe-bench/sites/apps/helpdesk/helpdesk/__init__.py ] && [ -f /home/frappe/frappe-bench/sites/apps/telephony/telephony/__init__.py ]; do
                                echo "Waiting for persisted Helpdesk apps"
                                sleep 5
                              done
                          volumeMounts:
                            - name: sites-dir
                              mountPath: /home/frappe/frappe-bench/sites
                    scheduler:
                      envVars: *helpdeskEnv
                      initContainers: *waitForHelpdeskApps
                    default:
                      envVars: *helpdeskEnv
                      initContainers: *waitForHelpdeskApps
                    short:
                      envVars: *helpdeskEnv
                      initContainers: *waitForHelpdeskApps
                    long:
                      envVars: *helpdeskEnv
                      initContainers: *waitForHelpdeskApps

                  socketio:
                    envVars: *helpdeskEnv
                    initContainers: *waitForHelpdeskApps
            destination:
              server: https://kubernetes.default.svc
              namespace: erpnext
            syncPolicy:
              automated:
                prune: true
                selfHeal: true

          BOOTSTRAP_EOF
          ''
      );
      eval = lib.evalModules {
        specialArgs = { inherit inputs; argocdChart = flakeOutputs.argocdChart; };
        modules = [
          ./modules/top.nix
        ];
      };
    in
      eval.config.flake // flakeOutputs // { inherit argocdBootstrap; };
}
