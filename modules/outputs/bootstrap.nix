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

  # Bootstrap output that merges gitea, argocd, and cloudflare
  bootstrapFor = system:
    let
      pkgs = pkgsFor system;
      charts = chartsFor system;
      helmLib = helmLibFor system;
      kubelib = inputs.nix-kube-generators.lib { inherit pkgs; };
      
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
                argocdServerAdminPassword = "$2a$10$bX.6MmE5x1n.KlTA./3ax.xXzgP5CzLu1CyFyvMnEeh.vN9tDVVLC";
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
            hostname = "verdaccio.quadtech.dev";
            service = "http://192.168.1.240:80";
          }
          {
            hostname = "minecraft.quadtech.dev";
            service = "tcp://192.168.1.240:25565";
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
apiVersion: v1
kind: ConfigMap
metadata:
  name: gitea-actions-config
  namespace: gitea
data:
  config.yaml: |
    runner:
      url: https://gitea.quadtech.dev
      extra:
        - ubuntu-latest
        - linux
        - x86_64
        - self-hosted
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
      initContainers:
        - name: init
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              echo "Waiting for Gitea to be ready..."
              until curl -sf http://gitea-http.gitea.svc.cluster.local:3000 > /dev/null 2>&1; do
                echo "Waiting..."
                sleep 5
              done
              echo "Gitea is ready"
      containers:
        - name: act-runner
          image: docker.gitea.com/act_runner:0.2.13
          env:
            - name: CONFIG_FILE
              value: /runner/config.yaml
            - name: GITEA_RUNNER_TOKEN
              valueFrom:
                secretKeyRef:
                  name: gitea-runner-token
                  key: token
          volumeMounts:
            - name: runner-config
              mountPath: /runner
              readOnly: true
            - name: runner-data
              mountPath: /data
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
          configMap:
            name: gitea-actions-config
        - name: runner-data
          emptyDir: {}
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
      - name: externalURL
        value: https://harbor.quadtech.dev
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
      - name: jobservice.replicas
        value: "1"
      - name: registry.replicas
        value: "1"
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
          rcon.password: "minecraft-rcon-password"
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

        # Create combined file
        cat $out/00-metallb.yaml > $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/00-metallb-crds.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/01-ingress-nginx.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02-longhorn.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/03-gitea.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/04-gitea-runner-secret.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/04-gitea-actions.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
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
        cat $out/13-verdaccio-argocd-app.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/11-minecraft-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/14-minecraft-argocd-app.yaml >> $out/bootstrap.yaml
      '';

in
{
  config.flake.bootstrap = forAllSystems bootstrapFor;
}
