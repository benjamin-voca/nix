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


  # Bootstrap output that merges forgejo, argocd, and cloudflare
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

      # Rook/Ceph operator and cluster charts for storage
      rookCephChart = existingCharts."rook-ceph";
      rookCephClusterChart = existingCharts."rook-ceph-cluster";

      # Harbor and monitoring charts rendered from repo-managed values
      harborChart = existingCharts.harbor;
      monitoringChart = existingCharts.prometheus;

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
        metrics = "0.0.0.0:2002";
        no-autoupdate = true;
        ingress = [
          {
            hostname = "backbone-01.quadtech.dev";
            service = "ssh://localhost:22";
          }
          {
            hostname = "forge-ssh.quadtech.dev";
            service = "tcp://127.0.0.1:32222";
          }
          {
            hostname = "forge.quadtech.dev";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "argocd.quadtech.dev";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "helpdesk.quadtech.dev";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "harbor.quadtech.dev";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "educourses-pd.com";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "www.educourses-pd.com";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "verdaccio.quadtech.dev";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "minecraft.quadtech.dev";
            service = "tcp://127.0.0.1:25565";
          }
          {
            hostname = "edukurs.quadtech.dev";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "batllavatourist.quadtech.dev";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "quadpacienti.quadtech.dev";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "openclaw.quadtech.dev";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "grafana.quadtech.dev";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "api.orkestr-os.com";
            service = "http://127.0.0.1:80";
          }
          {
            hostname = "*.quadtech.dev";
            service = "http://127.0.0.1:80";
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

        # Create argocd namespace and deploy ArgoCD chart
        cat > $out/01a-argocd-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
  labels:
    app.kubernetes.io/name: argocd
EOF

        cp ${argocdChart} $out/01b-argocd.yaml
        
        # Copy Rook/Ceph operator and cluster charts
        cp ${rookCephChart} $out/02-rook-ceph.yaml
        cp ${rookCephClusterChart} $out/03-rook-ceph-cluster.yaml
        chmod u+w $out/03-rook-ceph-cluster.yaml

        # Drop immutable legacy ceph-filesystem StorageClass object from rendered chart
        # and rely on the managed ceph-filesystem-csi StorageClass.
        OUT="$out" ${pkgs.python3}/bin/python - <<'PY'
import os
import pathlib

path = pathlib.Path(os.environ["OUT"]) / "03-rook-ceph-cluster.yaml"
docs = path.read_text().split("\n---\n")
filtered = []
for doc in docs:
    content = doc.strip()
    if not content:
        continue
    if "kind: StorageClass" in doc and "name: ceph-filesystem" in doc:
        continue
    filtered.append(content)
path.write_text("\n---\n".join(filtered) + "\n")
PY

        # Copy CNPG operator chart
        cp ${existingCharts.cloudnative-pg} $out/02a-cnpg-operator.yaml

        # Copy Harbor and monitoring charts from declarative chart configs
        cp ${harborChart} $out/11-harbor-chart.yaml
        cp ${monitoringChart} $out/12-monitoring-chart.yaml

        # Strip last-applied-configuration annotations from CRDs to avoid the
        # metadata.annotations 256KiB limit when manifests were previously
        # bootstrapped with client-side apply.
        OUT="$out" ${pkgs.python3}/bin/python - <<'PY'
import os
from pathlib import Path

target_files = [
    "01b-argocd.yaml",
    "02-rook-ceph.yaml",
    "02a-cnpg-operator.yaml",
    "12-monitoring-chart.yaml",
]


def strip_last_applied_annotation(document: str) -> str:
    if "kind: CustomResourceDefinition" not in document:
        return document

    lines = document.splitlines()
    cleaned = []
    index = 0

    while index < len(lines):
        line = lines[index]
        if "kubectl.kubernetes.io/last-applied-configuration:" in line:
            indent = len(line) - len(line.lstrip(" "))
            index += 1

            while index < len(lines):
                next_line = lines[index]
                if next_line.strip() == "":
                    index += 1
                    continue

                next_indent = len(next_line) - len(next_line.lstrip(" "))
                if next_indent > indent:
                    index += 1
                    continue

                break

            continue

        cleaned.append(line)
        index += 1

    return "\n".join(cleaned)


out_dir = Path(os.environ["OUT"])
for name in target_files:
    path = out_dir / name
    if not path.exists():
        continue

    # Files copied into $out are read-only by default.
    path.chmod(0o644)

    docs = path.read_text().split("\n---\n")
    cleaned_docs = []
    for doc in docs:
        if not doc.strip():
            continue
        cleaned_docs.append(strip_last_applied_annotation(doc.strip()))

    path.write_text("\n---\n".join(cleaned_docs) + "\n")
PY
        
        # Create CNPG cluster manifest for shared postgres
        cat > $out/02b-cnpg-cluster.yaml << 'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: shared-pg
  namespace: cnpg-system
spec:
  instances: 1
  storage:
    storageClass: ceph-block
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
  backup:
    barmanObjectStore:
      destinationPath: "s3://cnpg-backups/"
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

        # Create rook-ceph namespace
        cat > $out/02d-rook-ceph-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: rook-ceph
  labels:
    app.kubernetes.io/name: rook-ceph
EOF

        # Create Ceph RGW user used by CNPG backups
        cat > $out/02e-ceph-rgw-cnpg-user.yaml << 'EOF'
apiVersion: ceph.rook.io/v1
kind: CephObjectStoreUser
metadata:
  name: cnpg-backups
  namespace: rook-ceph
spec:
  store: ceph-objectstore
  displayName: CNPG Backups
EOF

        # Create deterministic RGW bucket for CNPG backups
        cat > $out/02f-ceph-rgw-cnpg-bucket-job.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: ceph-rgw-cnpg-backups-bucket
  namespace: rook-ceph
spec:
  backoffLimit: 6
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: create-bucket
          image: amazon/aws-cli:2.17.40
          env:
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-object-user-ceph-objectstore-cnpg-backups
                  key: AccessKey
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-object-user-ceph-objectstore-cnpg-backups
                  key: SecretKey
            - name: AWS_DEFAULT_REGION
              value: us-east-1
          command:
            - /bin/sh
            - -ec
            - |
              ENDPOINT="http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local"
              if aws --endpoint-url "$ENDPOINT" s3api head-bucket --bucket cnpg-backups >/dev/null 2>&1; then
                echo "Bucket cnpg-backups already exists"
                exit 0
              fi
              aws --endpoint-url "$ENDPOINT" s3api create-bucket --bucket cnpg-backups
              echo "Bucket cnpg-backups created"
EOF

        # Create scheduled CNPG backup for edukurs cluster
        cat > $out/02g-edukurs-cnpg-scheduled-backup.yaml << 'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: edukurs-db-ceph-hourly
  namespace: edukurs
spec:
  schedule: "0 0 * * * *"
  immediate: true
  backupOwnerReference: cluster
  method: barmanObjectStore
  cluster:
    name: edukurs-db-ceph
EOF

        # Create scheduled CNPG backup for forgejo cluster
        cat > $out/02h-forgejo-cnpg-scheduled-backup.yaml << 'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: forgejo-db-hourly
  namespace: forgejo
spec:
  schedule: "0 15 * * * *"
  immediate: true
  backupOwnerReference: cluster
  method: barmanObjectStore
  cluster:
    name: forgejo-db
EOF

        # Create forgejo namespace
        cat > $out/02i-forgejo-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: forgejo
  labels:
    app.kubernetes.io/name: forgejo
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
    repoURL: https://forge.quadtech.dev/QuadCoreTech/edukurs.git
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
    repoURL: https://forge.quadtech.dev/QuadCoreTech/batllavatourist.git
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
    repoURL: https://forge.quadtech.dev/QuadCoreTech/quadpacienti.git
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
        
      # Copy forgejo chart from existing charts
        cp ${existingCharts.forgejo} $out/03-forgejo.yaml
        chmod u+w $out/03-forgejo.yaml

        # Normalize Forgejo service targetPort for schema validation.
        OUT="$out" ${pkgs.python3}/bin/python - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["OUT"]) / "03-forgejo.yaml"
docs = path.read_text().split("\n---\n")
updated_docs = []
for doc in docs:
    if "kind: Service" in doc and "\n  name: forgejo-http\n" in doc:
        doc = doc.replace("targetPort: \n", "targetPort: 3000\n")
    updated_docs.append(doc)
path.write_text("\n---\n".join(updated_docs) + "\n")
PY

        # Ensure Forgejo shared storage claim exists on Ceph
        cat > $out/03a-forgejo-shared-storage-ceph-pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: forgejo-shared-storage-ceph-csi
  namespace: forgejo
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ceph-filesystem-csi
  resources:
    requests:
      storage: 50Gi
EOF

        # Ensure Forgejo DB cluster is explicitly Ceph-backed
        cat > $out/03b-forgejo-db-storageclass-patch.yaml << 'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: forgejo-db
  namespace: forgejo
spec:
  storage:
    storageClass: ceph-block
    size: 10Gi
  instances: 3
EOF
        
        # Create forgejo runner token secret (base64 encoded - will be replaced with actual secret via SOPS or external secret operator)
        cat > $out/04-forgejo-runner-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: forgejo-runner-token
  namespace: forgejo
type: Opaque
stringData:
  token: RUNNER_TOKEN_PLACEHOLDER
EOF
        
        # Copy forgejo-actions chart from existing charts
        cp ${existingCharts.forgejo-actions} $out/04-forgejo-actions.yaml
        chmod u+w $out/04-forgejo-actions.yaml

        # Inject missing StatefulSet serviceName required by Kubernetes schema.
        OUT="$out" ${pkgs.python3}/bin/python - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["OUT"]) / "04-forgejo-actions.yaml"
docs = path.read_text().split("\n---\n")
updated_docs = []
for doc in docs:
    if "kind: StatefulSet" in doc and "\n  name: forgejo-actions-act-runner\n" in doc and "serviceName:" not in doc:
        doc = doc.replace(
            "\nspec:\n  replicas:",
            "\nspec:\n  serviceName: forgejo-actions-act-runner\n  replicas:",
            1,
        )
    updated_docs.append(doc)
path.write_text("\n---\n".join(updated_docs) + "\n")
PY

        if [ ! -s "$out/04-forgejo-actions.yaml" ]; then
          echo "forgejo-actions chart render is empty; skipping" >&2
          rm -f "$out/04-forgejo-actions.yaml"
        fi

        # Create Forgejo repository credentials for ArgoCD
        # NOTE: This is now applied via argocd-deploy service after deployment
        # The service reads from /run/secrets/argocd-forgejo-username and /run/secrets/argocd-forgejo-token
        # which are managed via SOPS in secrets/backbone-01.yaml

        # Create ArgoCD Repository CR for Forgejo
        cat > $out/04-argocd-forgejo-repo.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Repository
metadata:
  name: forgejo-quadtech
  namespace: argocd
spec:
  type: git
  url: https://forge.quadtech.dev/QuadCoreTech
  usernameSecret:
    name: argocd-forgejo-creds
    key: username
  passwordSecret:
    name: argocd-forgejo-creds
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

        # Create harbor namespace inline
        cat > $out/09-harbor-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: harbor
  labels:
    app.kubernetes.io/name: harbor
EOF

        # Ensure Harbor Ceph PVC claims exist
        cat > $out/09a-harbor-pvcs-ceph.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: harbor-registry-ceph
  namespace: harbor
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 100Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: harbor-jobservice-ceph
  namespace: harbor
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: harbor-database-ceph
  namespace: harbor
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: harbor-redis-ceph
  namespace: harbor
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: harbor-trivy-ceph
  namespace: harbor
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 5Gi
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
  storageClassName: ceph-block
  resources:
    requests:
      storage: 10Gi
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
EOF

        # Ensure ERPNext namespace exists before helpdesk redirect ingress
        cat > $out/12aa-erpnext-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: erpnext
  labels:
    app.kubernetes.io/name: erpnext
EOF

        # Redirect legacy Helpdesk path to Desk module route
        cat > $out/12a-erpnext-helpdesk-redirect-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: erpnext-helpdesk-redirect
  namespace: erpnext
  annotations:
    nginx.ingress.kubernetes.io/permanent-redirect: /desk/helpdesk
    nginx.ingress.kubernetes.io/permanent-redirect-code: "308"
spec:
  ingressClassName: nginx
  rules:
  - host: helpdesk.quadtech.dev
    http:
      paths:
      - path: /helpdesk
        pathType: Exact
        backend:
          service:
            name: erpnext
            port:
              number: 8080
      - path: /helpdesk/
        pathType: Prefix
        backend:
          service:
            name: erpnext
            port:
              number: 8080
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

        # Create monitoring namespace
        cat > $out/11-monitoring-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    app.kubernetes.io/name: monitoring
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
          storageClass: ceph-block
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
            cpu: 500m
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
        cat $out/01a-argocd-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/01b-argocd.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02d-rook-ceph-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02-rook-ceph.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/03-rook-ceph-cluster.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02e-ceph-rgw-cnpg-user.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02f-ceph-rgw-cnpg-bucket-job.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02g-edukurs-cnpg-scheduled-backup.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02i-forgejo-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02h-forgejo-cnpg-scheduled-backup.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02a-cnpg-operator.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02b-cnpg-cluster.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02c-cnpg-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/03-forgejo.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/03a-forgejo-shared-storage-ceph-pvc.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/03b-forgejo-db-storageclass-patch.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/04-forgejo-runner-secret.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        if [ -f "$out/04-forgejo-actions.yaml" ]; then
          cat $out/04-forgejo-actions.yaml >> $out/bootstrap.yaml
          echo "---" >> $out/bootstrap.yaml
        fi
        # ArgoCD Forgejo credentials now applied via argocd-deploy service (not in bootstrap)
        cat $out/05-cloudflared-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/05-cloudflared-configmap.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/06-cloudflared-deployment.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/09-harbor-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/09a-harbor-pvcs-ceph.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/10-verdaccio-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/10a-verdaccio-pvc.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/11-harbor-chart.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/12-harbor-ingress.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/12aa-erpnext-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/12a-erpnext-helpdesk-redirect-ingress.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/13-verdaccio-argocd-app.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/11-monitoring-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/12-monitoring-chart.yaml >> $out/bootstrap.yaml
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
