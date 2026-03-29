{ config, lib, inputs, ... }:

let
  systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  forAllSystems = lib.genAttrs systems;

  # Helper to get pkgs for a system
  pkgsFor = system: inputs.nixpkgs.legacyPackages.${system};

  # Helper to get helmLib for a system  
  helmLibFor = system:
    let
      pkgs = pkgsFor system;
    in
      import ../../lib/helm {
        inherit (inputs) nixhelm nix-kube-generators;
        inherit pkgs system;
      };

  # Get charts from nixhelm
  chartsFor = system: inputs.nixhelm.chartsDerivations.${system};

  # Import composable library - for modular k8s manifest building
  # This library provides reusable functions for:
  # - Namespace creation (mkNamespace)
  # - ArgoCD Application building (mkArgoHelmApp)
  # - Cloudflared configuration (mkCloudflared*)
  # - Gitea runner resources (mkGiteaRunner*)
  # - MetalLB CRDs (mkMetallbCRDs)
  # - Common resource presets
  composableFor = system:
    let
      pkgs = pkgsFor system;
    in
      import ../../lib/helm/composable.nix {
        inherit pkgs;
      };


  # Bootstrap output that merges gitea, argocd, and cloudflare
  bootstrapFor = system:
    let
      pkgs = pkgsFor system;
      charts = chartsFor system;
      helmLib = helmLibFor system;
      kubelib = inputs.nix-kube-generators.lib { inherit pkgs; };
      
      # Use the composable library for manifest building
      composable = composableFor system;

      openclawBootstrap = import ./bootstrap/openclaw.nix {
        inherit lib pkgs;
      };
      
      # Import existing charts from lib/helm/charts
      existingCharts = import ../../lib/helm/charts { inherit helmLib; };

      # MetalLB chart - use nixhelm's chart derivation directly
      # Note: MetalLB 0.15+ uses CRDs for configuration instead of configInline
      metallbChart = pkgs.lib.pipe
        {
          name = "metallb";
          chart = charts.metallb.metallb;
          namespace = "metallb";
          values = {
            # Use the CRD-based configuration (L2Advertisement and IPAddressPool)
            controller = {
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "128Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "256Mi";
                };
              };
            };
            speaker = {
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "200m";
                  memory = "128Mi";
                };
              };
            };
          };
        }
        [
          kubelib.buildHelmChart
        ];

      # Ingress-nginx chart with LoadBalancer (gets IP from MetalLB)
      ingressNginxChart = pkgs.lib.pipe
        {
          name = "ingress-nginx";
          chart = charts.kubernetes-ingress-nginx.ingress-nginx;
          namespace = "ingress-nginx";
          values = {
            controller = {
              service = {
                type = "LoadBalancer";
              };
            };
          };
        }
        [
          kubelib.buildHelmChart
        ];

      # Longhorn chart for persistent storage
      longhornChart = pkgs.lib.pipe
        {
          name = "longhorn";
          chart = charts.longhorn.longhorn;
          namespace = "longhorn-system";
          values = {
            persistence = {
              defaultClass = true;
              defaultClassReplicaCount = 1;
            };
            service = {
              ui = {
                type = "ClusterIP";
              };
            };
          };
        }
        [
          kubelib.buildHelmChart
        ];

      # ArgoCD chart configuration  
      argocdChart = pkgs.lib.pipe
        {
          name = "argocd";
          chart = charts.argoproj.argo-cd;
          namespace = "argocd";
          values = {
            global = {
              domain = "argocd.quadtech.dev";
            };
            configs = {
              cm = {
                "server.insecure" = true;
                "server.forceHttp" = true;
                url = "http://argocd.quadtech.dev";
              };
              params = {
                "server.insecure" = true;
                "server.forceHttp" = true;
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
            redis.enabled = true;
            redis-ha.enabled = false;
            controller.replicas = 1;
            repoServer.replicas = 1;
            applicationSet.enabled = true;
            notifications.enabled = true;
            global.image.tag = "v2.9.3";
          };
        }
        [
          kubelib.buildHelmChart
        ];

      # Cloudflared config content as string
      cloudflaredConfigContent = builtins.toJSON {
        tunnel = "b6bac523-be70-4625-8b67-fa78a9e1c7a5";
        credentials-file = "/etc/cloudflared/creds/credentials.json";
        metrics = "0.0.0.0:2000";
        no-autoupdate = true;
        ingress = [
          {
            hostname = "backbone-01.quadtech.dev";
            service = "ssh://localhost:22";
          }
          {
            hostname = "gitea-ssh.quadtech.dev";
            service = "tcp://192.168.1.240:32222";
          }
          {
            hostname = "gitea.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "argocd.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "helpdesk.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "harbor.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "educourses-pd.com";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "www.educourses-pd.com";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "verdaccio.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "minecraft.quadtech.dev";
            service = "tcp://192.168.1.240:25565";
          }
          {
            hostname = "edukurs.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "batllavatourist.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "quadpacienti.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "openclaw.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "grafana.k8s.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "*.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            service = "http_status:404";
          }
        ];
      };

      # Cloudflared deployment with config file
      cloudflaredManifest = pkgs.writeText "cloudflared.yaml" (builtins.toJSON {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = "cloudflared";
          namespace = "cloudflared";
          labels = {
            app = "cloudflared";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "cloudflared";
          template = {
            metadata.labels.app = "cloudflared";
            spec = {
              hostNetwork = true;
              containers = [{
                name = "cloudflared";
                image = "cloudflare/cloudflared:latest";
                command = [ "cloudflared" "tunnel" "--config" "/etc/cloudflared/config/config.yaml" "run" ];
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/etc/cloudflared/config";
                    readOnly = true;
                  }
                  {
                    name = "creds";
                    mountPath = "/etc/cloudflared/creds";
                    readOnly = true;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "256Mi";
                  };
                };
              }];
              volumes = [
                {
                  name = "config";
                  configMap = {
                    name = "cloudflared-config";
                    items = [
                      {
                        key = "config.yaml";
                        path = "config.yaml";
                      }
                    ];
                  };
                }
                {
                  name = "creds";
                  secret = {
                    secretName = "cloudflared-credentials";
                  };
                }
              ];
            };
          };
        };
      });

      # Create namespace for cloudflared
      cloudflaredNamespace = pkgs.writeText "cloudflared-namespace.yaml" (builtins.toJSON {
        apiVersion = "v1";
        kind = "Namespace";
        metadata = {
          name = "cloudflared";
          labels = {
            "app.kubernetes.io/name" = "cloudflared";
          };
        };
      });

      # Note: cloudflared credentials are mounted via Kubernetes secret
      # The secret 'cloudflared-credentials' should be created from sops-decrypted credentials

      # NodePort service for direct SSH access on fixed port 2222
      # Configure your router to forward port 2222 to the node's IP
      giteaSSHNodePort = pkgs.writeText "gitea-ssh-nodeport.yaml" (builtins.toJSON {
        apiVersion = "v1";
        kind = "Service";
        metadata = {
          name = "gitea-ssh-nodeport";
          namespace = "gitea";
          annotations = {
            "external-dns.alpha.kubernetes.io/hostname" = "gitea-ssh.quadtech.dev";
          };
        };
        spec = {
          type = "NodePort";
          ports = [{
            port = 22;
            targetPort = 22;
            nodePort = 32222;
            protocol = "TCP";
          }];
          selector = {
            "app.kubernetes.io/name" = "gitea";
            "app.kubernetes.io/instance" = "gitea";
          };
        };
      });

      # MetalLB CRDs for IP address pool configuration (MetalLB 0.15+ uses CRDs)
      metallbIPAddressPool = ''
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
'';

    in
      # Combine all charts and manifests into a single bootstrap output
      # Use runCommand with explicit system to avoid cross-compilation issues
      let
        cloudflaredDeployment = ''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: cloudflared
  labels:
    app: cloudflared
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      hostNetwork: true
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:latest
        command: ["cloudflared", "tunnel", "--config", "/etc/cloudflared/config/config.yaml", "run"]
        volumeMounts:
        - name: config
          mountPath: /etc/cloudflared/config
          readOnly: true
        - name: creds
          mountPath: /etc/cloudflared/creds
          readOnly: true
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
      volumes:
      - name: config
        configMap:
          name: cloudflared-config
          items:
          - key: config.yaml
            path: config.yaml
      - name: creds
        secret:
          secretName: cloudflared-credentials
'';
      in
      pkgs.runCommand "bootstrap-manifests"
        {
          inherit system;
          preferLocalBuild = true;
        }
        ''
        set -euo pipefail
        
        mkdir -p $out
        
        # Copy metallb chart first (needed for LoadBalancer)
        cp ${metallbChart} $out/00-metallb.yaml
        
        # Write MetalLB CRDs for IP pool
        cat > $out/00-metallb-crds.yaml << 'METALLB_CRDS_EOF'
${metallbIPAddressPool}
METALLB_CRDS_EOF
        
        # Copy ingress-nginx chart (will get IP from MetalLB)
        cp ${ingressNginxChart} $out/01-ingress-nginx.yaml
        
        # Copy Longhorn chart (for persistent storage)
        cp ${longhornChart} $out/02-longhorn.yaml
        
        # Copy CNPG operator chart
        cp ${existingCharts.cloudnative-pg} $out/02a-cnpg-operator.yaml
        
        # Create CNPG cluster manifest for shared postgres
        cat > $out/02b-cnpg-cluster.yaml << 'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: shared-pg
  namespace: cnpg-system
spec:
  instances: 1
  imageName: docker.io/cloudnative-pg/container:1.22.1
  storage:
    storageClass: longhorn
    size: 10Gi
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  bootstrap:
    initdb:
      database: edukurs
      owner: edukurs
      secret:
        name: shared-pg-app
  postgresql:
    pg_hba:
      - host all all 0.0.0.0/0 md5
      - host all all ::0/0 md5
  monitoring:
    enabled: false
---
apiVersion: v1
kind: Secret
metadata:
  name: shared-pg-app
  namespace: cnpg-system
type: Opaque
stringData:
  username: edukurs
  password: PLACEHOLDER
  dbname: edukurs
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: batllavatourist
  namespace: cnpg-system
spec:
  cluster:
    name: shared-pg
  owner: app
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: quadpacienti
  namespace: cnpg-system
spec:
  cluster:
    name: shared-pg
  owner: app
EOF

        # Create cnpg-system namespace for the CNPG operator
        cat > $out/02c-cnpg-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: cnpg-system
  labels:
    app.kubernetes.io/name: cloudnative-pg
EOF

        # Create app namespaces
        cat > $out/15-edukurs-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: edukurs
  labels:
    app.kubernetes.io/name: edukurs
EOF

        cat > $out/15-batllavatourist-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: batllavatourist
  labels:
    app.kubernetes.io/name: batllavatourist
EOF

        cat > $out/15-quadpacienti-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: quadpacienti
  labels:
    app.kubernetes.io/name: quadpacienti
EOF

        # Create ArgoCD Application for EduKurs (placeholder - needs Docker image built)
        cat > $out/16-edukurs-argocd-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: edukurs
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://gitea.quadtech.dev/QuadCoreTech/edukurs.git
    path: k8s
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: edukurs
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

        # Create ArgoCD Application for BatllavaTourist (placeholder - needs Docker image built)
        cat > $out/16-batllavatourist-argocd-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: batllavatourist
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://gitea.quadtech.dev/QuadCoreTech/batllavatourist.git
    path: k8s
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: batllavatourist
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

        # Create ArgoCD Application for QuadPacienti (placeholder - needs Docker image built)
        cat > $out/16-quadpacienti-argocd-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: quadpacienti
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://gitea.quadtech.dev/QuadCoreTech/quadpacienti.git
    path: k8s
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: quadpacienti
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
        
        # Copy gitea chart from existing charts
        cp ${existingCharts.gitea} $out/03-gitea.yaml
        
        # Create gitea runner token secret (base64 encoded - will be replaced with actual secret via SOPS or external secret operator)
        cat > $out/04-gitea-runner-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: gitea-runner-token
  namespace: gitea
type: Opaque
stringData:
  token: RUNNER_TOKEN_PLACEHOLDER
EOF
        
        # Create gitea-actions runner deployment inline
        cat > $out/04-gitea-actions.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitea-actions
  namespace: gitea
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: gitea-actions
  namespace: gitea
spec:
  serviceName: gitea-actions
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: gitea-actions
  template:
    metadata:
      labels:
        app.kubernetes.io/name: gitea-actions
    spec:
      serviceAccountName: gitea-actions
      containers:
        - name: act-runner
          image: docker.gitea.com/act_runner:0.2.13
          command:
            - sh
            - -c
            - |
              cat > /runner/config.yaml << CONFIGEOF
              runner:
                url: https://gitea.quadtech.dev
                token: $(cat /run/secrets/token)
                extra:
                  - ubuntu-latest
                  - linux
                  - x86_64
                  - self-hosted
CONFIGEOF
              exec /bin/act_runner daemon --config /runner/config.yaml
          env:
            - name: GITEA_RUNNER_TOKEN
              valueFrom:
                secretKeyRef:
                  name: gitea-runner-token
                  key: token
          volumeMounts:
            - name: runner-config
              mountPath: /runner
            - name: runner-data
              mountPath: /data
            - name: runner-token
              mountPath: /run/secrets
              readOnly: true
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 1000m
              memory: 1Gi
        - name: dind
          image: docker:28.3.3-dind
          securityContext:
            privileged: true
          volumeMounts:
            - name: runner-data
              mountPath: /var/lib/docker
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 2000m
              memory: 2Gi
      volumes:
        - name: runner-config
          emptyDir: {}
        - name: runner-data
          emptyDir: {}
        - name: runner-token
          secret:
            secretName: gitea-runner-token
EOF

        # Create Gitea repository credentials for ArgoCD
        # NOTE: These are now applied via argocd-deploy service after deployment
        # The service reads from /run/secrets/argocd-gitea-username and /run/secrets/argocd-gitea-token
        # which are managed via SOPS in secrets/backbone-01.yaml

        # Create ArgoCD Repository CR for Gitea
        cat > $out/04-argocd-gitea-repo.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Repository
metadata:
  name: gitea-quadtech
  namespace: argocd
spec:
  type: git
  url: https://gitea.quadtech.dev/QuadCoreTech
  usernameSecret:
    name: argocd-gitea-creds
    key: username
  passwordSecret:
    name: argocd-gitea-creds
    key: password
EOF
        
        # Create cloudflared namespace inline
        cat > $out/05-cloudflared-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: cloudflared
  labels:
    app.kubernetes.io/name: cloudflared
EOF
        
        # Create cloudflared configmap inline
        cat > $out/05-cloudflared-configmap.yaml << 'CONFIGMAP_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared-config
  namespace: cloudflared
data:
  config.yaml: |
CONFIGMAP_EOF
        echo '${cloudflaredConfigContent}' | sed 's/^/    /' >> $out/05-cloudflared-configmap.yaml
        
        # Write cloudflared deployment inline
        cat > $out/06-cloudflared-deployment.yaml << 'DEPLOYMENT_EOF'
${cloudflaredDeployment}
DEPLOYMENT_EOF

        # Create gitea SSH NodePort inline
        cat > $out/07-gitea-ssh-nodeport.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: gitea-ssh-nodeport
  namespace: gitea
  annotations:
    external-dns.alpha.kubernetes.io/hostname: gitea-ssh.quadtech.dev
spec:
  type: NodePort
  ports:
  - port: 22
    targetPort: 2223
    nodePort: 32222
    protocol: TCP
  selector:
    app.kubernetes.io/name: gitea
    app.kubernetes.io/instance: gitea
EOF

        # Create harbor namespace inline
        cat > $out/09-harbor-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: harbor
  labels:
    app.kubernetes.io/name: harbor
EOF

        # Create verdaccio namespace inline
        cat > $out/10-verdaccio-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: verdaccio
  labels:
    app.kubernetes.io/name: verdaccio
EOF

        # Create minecraft namespace inline
        cat > $out/11-minecraft-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: minecraft
  labels:
    app.kubernetes.io/name: minecraft
EOF

        # Create Verdaccio PVC
        cat > $out/10a-verdaccio-pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: verdaccio-data
  namespace: verdaccio
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
EOF

        # Create ArgoCD Application for Longhorn (storage)
        cat > $out/10-longhorn-argocd-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: longhorn
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    chart: longhorn
    repoURL: https://charts.longhorn.io
    targetRevision: 1.11.0
  destination:
    server: https://kubernetes.default.svc
    namespace: longhorn-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

        # Create ArgoCD Application for Harbor
        cat > $out/11-harbor-argocd-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: harbor
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    chart: harbor
    repoURL: https://helm.goharbor.io
    targetRevision: 1.18.1
    helm:
      parameters:
      - name: expose.ingress.hosts.core
        value: harbor.quadtech.dev
      - name: expose.tls.enabled
        value: "true"
      - name: expose.tls.certSource
        value: auto
      - name: expose.ingress.enabled
        value: "false"
      - name: expose.ingress.annotations.nginx\.ingress\.kubernetes\.io/ssl-redirect
        value: "false"
      - name: expose.ingress.annotations.nginx\.ingress\.kubernetes\.io/backend-protocol
        value: HTTP
      - name: expose.ingress.annotations.nginx\.ingress\.kubernetes\.io/proxy-body-size
        value: "0"
      - name: externalURL
        value: https://harbor.quadtech.dev
      - name: harborAdminPassword
        value: PLACEHOLDER
      - name: persistence.enabled
        value: "true"
      - name: persistence.resourcePolicy
        value: keep
      - name: persistence.persistentVolumeClaim.registry.storageClass
        value: longhorn
      - name: persistence.persistentVolumeClaim.registry.size
        value: 100Gi
      - name: persistence.persistentVolumeClaim.database.size
        value: 10Gi
      - name: persistence.persistentVolumeClaim.redis.size
        value: 5Gi
      - name: persistence.persistentVolumeClaim.trivy.size
        value: 10Gi
      - name: database.type
        value: internal
      - name: redis.type
        value: internal
      - name: portal.replicas
        value: "1"
      - name: core.replicas
        value: "1"
      - name: core.autoredirect.enabled
        value: "false"
      - name: jobservice.replicas
        value: "1"
      - name: registry.replicas
        value: "1"
      - name: registry.credentials.username
        value: harbor_registry_user
      - name: registry.credentials.password
        value: PLACEHOLDER
      - name: registry.credentials.htpasswdString
        value: $2y$05$U.haVkY0IczOsQ46qpFH.eleok5nmZG/8fKQZw6.0UWRKBKrFtZ4G
      - name: trivy.enabled
        value: "true"
      - name: notary.enabled
        value: "false"
      - name: chartmuseum.enabled
        value: "false"
  destination:
    server: https://kubernetes.default.svc
    namespace: harbor
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

        # Create custom Ingress for Harbor
        # /v2/ must go through harbor-core for token-based Docker auth
        cat > $out/12-harbor-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: harbor-ingress
  namespace: harbor
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - harbor.quadtech.dev
    secretName: harbor-ingress
  rules:
  - host: harbor.quadtech.dev
    http:
      paths:
      - path: /api/
        pathType: Prefix
        backend:
          service:
            name: harbor-core
            port:
              number: 80
      - path: /service/
        pathType: Prefix
        backend:
          service:
            name: harbor-core
            port:
              number: 80
      - path: /v2/
        pathType: Prefix
        backend:
          service:
            name: harbor-core
            port:
              number: 80
      - path: /c/
        pathType: Prefix
        backend:
          service:
            name: harbor-core
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: harbor-portal
            port:
              number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: harbor-ingress-tls
  namespace: harbor
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - harbor.quadtech.dev
    secretName: harbor-ingress
EOF

        # Create ArgoCD Application for Verdaccio
        cat > $out/13-verdaccio-argocd-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: verdaccio
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    chart: verdaccio
    repoURL: https://charts.verdaccio.org
    targetRevision: 4.29.0
    helm:
      parameters:
      - name: service.type
        value: ClusterIP
      - name: ingress.enabled
        value: "true"
      - name: ingress.className
        value: nginx
      - name: ingress.hosts[0]
        value: verdaccio.quadtech.dev
      - name: persistence.enabled
        value: "true"
      - name: persistence.existingClaim
        value: verdaccio-data
  destination:
    server: https://kubernetes.default.svc
    namespace: verdaccio
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

        # Create ArgoCD Application for Minecraft
        cat > $out/14-minecraft-argocd-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: minecraft
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    chart: minecraft
    repoURL: https://itzg.github.io/minecraft-server-charts
    targetRevision: 5.1.1
    helm:
      valueFiles:
      - values.yaml
      values: |
        minecraftServer:
          eula: "TRUE"
          version: "1.21.4"
          gamemode: survival
          difficulty: normal
          allow-flight: true
          enable-rcon: true
          rcon.password: "PLACEHOLDER"
          rcon.port: 25575
          query.enabled: true
          query.port: 25565
        persistence:
          enabled: true
          storageClass: longhorn
          size: 20Gi
        service:
          type: LoadBalancer
          loadBalancerIP: 192.168.1.245
        ingress:
          enabled: true
          ingressClassName: nginx
          annotations:
            nginx.ingress.kubernetes.io/ssl-redirect: "false"
            nginx.ingress.kubernetes.io/proxy-body-size: "50m"
          hosts:
            - minecraft.quadtech.dev
          tls:
            - secretName: minecraft-tls
              hosts:
                - minecraft.quadtech.dev
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: 4000m
            memory: 6Gi
  destination:
    server: https://kubernetes.default.svc
    namespace: minecraft
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

        cp ${openclawBootstrap.manifests."17-openclaw-namespace.yaml"} $out/17-openclaw-namespace.yaml
        cp ${openclawBootstrap.manifests."17a-openclaw-pvc.yaml"} $out/17a-openclaw-pvc.yaml
        cp ${openclawBootstrap.manifests."17b-openclaw-configmap.yaml"} $out/17b-openclaw-configmap.yaml
        cp ${openclawBootstrap.manifests."17c-openclaw-deployment.yaml"} $out/17c-openclaw-deployment.yaml
        cp ${openclawBootstrap.manifests."17d-openclaw-service.yaml"} $out/17d-openclaw-service.yaml
        cp ${openclawBootstrap.manifests."17e-openclaw-ingress.yaml"} $out/17e-openclaw-ingress.yaml

        # Create combined file
        cat $out/00-metallb.yaml > $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/00-metallb-crds.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/01-ingress-nginx.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02-longhorn.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02a-cnpg-operator.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02b-cnpg-cluster.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02c-cnpg-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/03-gitea.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/04-gitea-runner-secret.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/04-gitea-actions.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        # ArgoCD Gitea credentials now applied via argocd-deploy service (not in bootstrap)
        # ArgoCD is deployed separately - skip 04-argocd.yaml
        cat $out/05-cloudflared-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/05-cloudflared-configmap.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/06-cloudflared-deployment.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/07-gitea-ssh-nodeport.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/09-harbor-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/10-verdaccio-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/10a-verdaccio-pvc.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/10-longhorn-argocd-app.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/11-harbor-argocd-app.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/12-harbor-ingress.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/13-verdaccio-argocd-app.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/11-minecraft-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/14-minecraft-argocd-app.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/15-edukurs-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/15-batllavatourist-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/15-quadpacienti-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/16-edukurs-argocd-app.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/16-batllavatourist-argocd-app.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/16-quadpacienti-argocd-app.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/17-openclaw-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/17a-openclaw-pvc.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/17b-openclaw-configmap.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/17c-openclaw-deployment.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/17d-openclaw-service.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/17e-openclaw-ingress.yaml >> $out/bootstrap.yaml
      '';

in
{
  config.flake.bootstrap = forAllSystems bootstrapFor;
}
