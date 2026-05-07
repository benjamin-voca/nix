{
  config,
  lib,
  inputs,
  ...
}: let
  systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
  forAllSystems = lib.genAttrs systems;

  pkgsFor = system: inputs.nixpkgs.legacyPackages.${system};
  helmLibFor = system: let
    pkgs = pkgsFor system;
  in
    import ../../lib/helm {
      inherit (inputs) nixhelm nix-kube-generators;
      inherit pkgs system;
    };

  chartsFor = system: inputs.nixhelm.chartsDerivations.${system};
  composableFor = system: let
    pkgs = pkgsFor system;
  in
    import ../../lib/helm/composable.nix {inherit pkgs;};

  bootstrapInfraFor = system: let
    pkgs = pkgsFor system;
    charts = chartsFor system;
    helmLib = helmLibFor system;
    kubelib = inputs.nix-kube-generators.lib {inherit pkgs;};

    composable = composableFor system;

    openclawBootstrap = import ./bootstrap/openclaw.nix {
      inherit lib pkgs;
    };

    existingCharts = import ../../lib/helm/charts {inherit helmLib;};

    metallbChart =
      pkgs.lib.pipe
      {
        name = "metallb";
        chart = charts.metallb.metallb;
        namespace = "metallb";
        values = {
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

    ingressNginxChart =
      pkgs.lib.pipe
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

    rookCephChart = existingCharts."rook-ceph";
    rookCephClusterChart = existingCharts."rook-ceph-cluster";

    harborChart = existingCharts.harbor;
    monitoringChart = existingCharts.prometheus;

    argocdChart =
      pkgs.lib.pipe
      {
        name = "argocd";
        chart = charts.argoproj.argo-cd;
        namespace = "argocd";
        values = (import ../../lib/argocd-values.nix {
          domain = "argocd.quadtech.dev";
          serverUrl = "http://argocd.quadtech.dev";
          imageTag = "v2.9.3";
          serverReplicas = 1;
          controllerReplicas = 1;
          repoServerReplicas = 1;
          enableApplicationSet = true;
          enableNotifications = true;
        })
        // {
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
          };
        };
      }
      [
        kubelib.buildHelmChart
      ];

    cloudflaredConfigContent = builtins.toJSON (import ../../lib/cloudflared-config.nix {
      tunnelId = "b6bac523-be70-4625-8b67-fa78a9e1c7a5";
      credentialsFile = "/etc/cloudflared/creds/credentials.json";
      metrics = "0.0.0.0:2002";
    });

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
            containers = [
              {
                name = "cloudflared";
                image = "cloudflare/cloudflared:latest";
                command = ["cloudflared" "tunnel" "--config" "/etc/cloudflared/config/config.yaml" "run"];
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
              }
            ];
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
      pkgs.runCommand "bootstrap-manifests-infra"
      {
        inherit system;
        preferLocalBuild = true;
      }
      ''
                set -euo pipefail

                mkdir -p $out

                cp ${metallbChart} $out/00-metallb.yaml

                cat > $out/00-metallb-crds.yaml << 'METALLB_CRDS_EOF'
        ${metallbIPAddressPool}
        METALLB_CRDS_EOF

                cp ${ingressNginxChart} $out/01-ingress-nginx.yaml

                cat > $out/01a-argocd-namespace.yaml << 'EOF'
        apiVersion: v1
        kind: Namespace
        metadata:
          name: argocd
          labels:
            app.kubernetes.io/name: argocd
        EOF

                cp ${argocdChart} $out/01b-argocd.yaml

                cp ${rookCephChart} $out/02-rook-ceph.yaml
                cp ${rookCephClusterChart} $out/03-rook-ceph-cluster.yaml
                chmod u+w $out/03-rook-ceph-cluster.yaml

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

                cp ${existingCharts.cloudnative-pg} $out/02a-cnpg-operator.yaml

                cp ${harborChart} $out/11-harbor-chart.yaml
                cp ${monitoringChart} $out/12-monitoring-chart.yaml

                cp ${existingCharts.grafana} $out/12-grafana-chart.yaml

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

            path.chmod(0o644)

            docs = path.read_text().split("\n---\n")
            cleaned_docs = []
            for doc in docs:
                if not doc.strip():
                    continue
                cleaned_docs.append(strip_last_applied_annotation(doc.strip()))

            path.write_text("\n---\n".join(cleaned_docs) + "\n")
        PY

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
        ---
        apiVersion: postgresql.cnpg.io/v1
        kind: Database
        metadata:
          name: grafana
          namespace: cnpg-system
        spec:
          cluster:
            name: shared-pg
          name: grafana
          owner: edukurs
        EOF

                cat > $out/02d-rook-ceph-namespace.yaml << 'EOF'
        apiVersion: v1
        kind: Namespace
        metadata:
          name: rook-ceph
          labels:
            app.kubernetes.io/name: rook-ceph
        EOF

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

                cat > $out/02i-forgejo-namespace.yaml << 'EOF'
        apiVersion: v1
        kind: Namespace
        metadata:
          name: forgejo
          labels:
            app.kubernetes.io/name: forgejo
        EOF

                cat > $out/02c-cnpg-namespace.yaml << 'EOF'
        apiVersion: v1
        kind: Namespace
        metadata:
          name: cnpg-system
          labels:
            app.kubernetes.io/name: cloudnative-pg
        EOF

                cat > $out/05-cloudflared-namespace.yaml << 'EOF'
        apiVersion: v1
        kind: Namespace
        metadata:
          name: cloudflared
          labels:
            app.kubernetes.io/name: cloudflared
        EOF

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

                cat > $out/06-cloudflared-deployment.yaml << 'DEPLOYMENT_EOF'
        ${cloudflaredDeployment}
        DEPLOYMENT_EOF

                cat > $out/09-harbor-namespace.yaml << 'EOF'
        apiVersion: v1
        kind: Namespace
        metadata:
          name: harbor
          labels:
            app.kubernetes.io/name: harbor
        EOF

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

                cat > $out/10-verdaccio-namespace.yaml << 'EOF'
        apiVersion: v1
        kind: Namespace
        metadata:
          name: verdaccio
          labels:
            app.kubernetes.io/name: verdaccio
        EOF

                cat > $out/11-minecraft-namespace.yaml << 'EOF'
        apiVersion: v1
        kind: Namespace
        metadata:
          name: minecraft
          labels:
            app.kubernetes.io/name: minecraft
        EOF

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

                cat > $out/12aa-erpnext-namespace.yaml << 'EOF'
        apiVersion: v1
        kind: Namespace
        metadata:
          name: erpnext
          labels:
            app.kubernetes.io/name: erpnext
        EOF

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

                cat > $out/11-monitoring-namespace.yaml << 'EOF'
        apiVersion: v1
        kind: Namespace
        metadata:
          name: monitoring
          labels:
            app.kubernetes.io/name: monitoring
        ---
        apiVersion: v1
        kind: Namespace
        metadata:
          name: grafana
          labels:
            app.kubernetes.io/name: grafana
        EOF

                cat > $out/12-grafana-db-secret.yaml << 'EOF'
        apiVersion: v1
        kind: Secret
        metadata:
          name: grafana-db
          namespace: grafana
        type: Opaque
        stringData:
          GF_DATABASE_TYPE: postgres
          GF_DATABASE_HOST: shared-pg-rw.cnpg-system.svc.cluster.local:5432
          GF_DATABASE_NAME: grafana
          GF_DATABASE_USER: edukurs
          GF_DATABASE_PASSWORD: PLACEHOLDER
          GF_SECURITY_ADMIN_PASSWORD: PLACEHOLDER
        EOF

                cat > $out/12a-grafana-ingress.yaml << 'EOF'
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: grafana
          namespace: grafana
          annotations:
            nginx.ingress.kubernetes.io/ssl-redirect: "false"
            nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
        spec:
          ingressClassName: nginx
          rules:
          - host: grafana.quadtech.dev
            http:
              paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: grafana
                    port:
                      number: 80
        EOF

                cp ${openclawBootstrap.manifests."17-openclaw-namespace.yaml"} $out/17-openclaw-namespace.yaml
                cp ${openclawBootstrap.manifests."17a-openclaw-pvc.yaml"} $out/17a-openclaw-pvc.yaml
                cp ${openclawBootstrap.manifests."17b-openclaw-configmap.yaml"} $out/17b-openclaw-configmap.yaml
                cp ${openclawBootstrap.manifests."17c-openclaw-deployment.yaml"} $out/17c-openclaw-deployment.yaml
                cp ${openclawBootstrap.manifests."17d-openclaw-service.yaml"} $out/17d-openclaw-service.yaml
                cp ${openclawBootstrap.manifests."17e-openclaw-ingress.yaml"} $out/17e-openclaw-ingress.yaml

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
                cat $out/11-monitoring-namespace.yaml >> $out/bootstrap.yaml
                echo "---" >> $out/bootstrap.yaml
                cat $out/12-monitoring-chart.yaml >> $out/bootstrap.yaml
                echo "---" >> $out/bootstrap.yaml
                cat $out/12-grafana-db-secret.yaml >> $out/bootstrap.yaml
                echo "---" >> $out/bootstrap.yaml
                cat $out/12-grafana-chart.yaml >> $out/bootstrap.yaml
                echo "---" >> $out/bootstrap.yaml
                cat $out/12a-grafana-ingress.yaml >> $out/bootstrap.yaml
                echo "---" >> $out/bootstrap.yaml
                cat $out/11-minecraft-namespace.yaml >> $out/bootstrap.yaml
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
in {
  config.flake.bootstrapInfra = forAllSystems bootstrapInfraFor;
}
