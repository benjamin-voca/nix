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
+    pkgs = pkgsFor system;
+  in
+    import ../../lib/helm/composable.nix {inherit pkgs;};

  bootstrapAppsFor = system: let
    pkgs = pkgsFor system;
    charts = chartsFor system;
    helmLib = helmLibFor system;
    kubelib = inputs.nix-kube-generators.lib {inherit pkgs;};

    composable = composableFor system;

    openclawBootstrap = import ./bootstrap/openclaw.nix {
      inherit lib pkgs;
    };

    existingCharts = import ../../lib/helm/charts {inherit helmLib;};

    forgejoChart = existingCharts.forgejo;
    forgejoActionsChart = existingCharts.forgejo-actions;
  in
    pkgs.runCommand "bootstrap-manifests-apps"
    {
+      inherit system;
+      preferLocalBuild = true;
    }
    ''
              set -euo pipefail

              mkdir -p $out

              # ── Forgejo (git service) ──
              cat > $out/02i-forgejo-namespace.yaml << 'EOF'
      apiVersion: v1
      kind: Namespace
      metadata:
        name: forgejo
        labels:
          app.kubernetes.io/name: forgejo
      EOF

              cp ${forgejoChart} $out/03-forgejo.yaml
              chmod u+w $out/03-forgejo.yaml

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

              cat > $out/03b-forgejo-db-storageclass-patch.yaml << 'EOF'
      apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      metadata:
        name: forgejo-db
        namespace: forgejo
      spec:
        storage:
          storageClass: ceph-block
          size: 20Gi
        instances: 3
      EOF

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

              cp ${forgejoActionsChart} $out/04-forgejo-actions.yaml
              chmod u+w $out/04-forgejo-actions.yaml

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

              # ── App namespaces ──
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

              # ── ArgoCD Applications ──
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

              # ── CNPG scheduled backups for apps ──
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

              # ── OpenClaw (bot) ──
              cp ${openclawBootstrap.manifests."17-openclaw-namespace.yaml"} $out/17-openclaw-namespace.yaml
              cp ${openclawBootstrap.manifests."17a-openclaw-pvc.yaml"} $out/17a-openclaw-pvc.yaml
              cp ${openclawBootstrap.manifests."17b-openclaw-configmap.yaml"} $out/17b-openclaw-configmap.yaml
              cp ${openclawBootstrap.manifests."17c-openclaw-deployment.yaml"} $out/17c-openclaw-deployment.yaml
              cp ${openclawBootstrap.manifests."17d-openclaw-service.yaml"} $out/17d-openclaw-service.yaml
              cp ${openclawBootstrap.manifests."17e-openclaw-ingress.yaml"} $out/17e-openclaw-ingress.yaml

              # ── Minecraft ──
              cat > $out/11-minecraft-namespace.yaml << 'EOF'
      apiVersion: v1
      kind: Namespace
      metadata:
        name: minecraft
        labels:
          app.kubernetes.io/name: minecraft
      EOF

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

              # ── Verdaccio ──
              cat > $out/10-verdaccio-namespace.yaml << 'EOF'
      apiVersion: v1
      kind: Namespace
      metadata:
        name: verdaccio
        labels:
          app.kubernetes.io/name: verdaccio
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

              # ── Orkestr ──
              cat > $out/18-orkestr-namespace.yaml << 'EOF'
      apiVersion: v1
      kind: Namespace
      metadata:
        name: orkestr
        labels:
          app.kubernetes.io/name: orkestr
      EOF

              cat > $out/18a-orkestr-ci-rbac.yaml << 'EOF'
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: gitea-ci
        namespace: orkestr
      ---
      apiVersion: rbac.authorization.k8s.io/v1
      kind: Role
      metadata:
        name: orkestr-ci-deployer
        namespace: orkestr
      rules:
        - apiGroups: ["apps"]
          resources: ["deployments"]
          verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
        - apiGroups: [""]
          resources: ["services", "configmaps", "secrets", "pods"]
          verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
        - apiGroups: ["networking.k8s.io"]
          resources: ["ingresses"]
          verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
        - apiGroups: ["postgresql.cnpg.io"]
          resources: ["clusters", "databases"]
          verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
        - apiGroups: [""]
          resources: ["persistentvolumeclaims"]
          verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
      ---
      apiVersion: rbac.authorization.k8s.io/v1
      kind: RoleBinding
      metadata:
        name: gitea-ci-deployer
        namespace: orkestr
      subjects:
        - kind: ServiceAccount
          name: gitea-ci
          namespace: orkestr
      roleRef:
        kind: Role
        name: orkestr-ci-deployer
        apiGroup: rbac.authorization.k8s.io
      ---
      apiVersion: v1
      kind: Secret
      metadata:
        name: gitea-ci-token
        namespace: orkestr
        annotations:
          kubernetes.io/service-account.name: gitea-ci
      type: kubernetes.io/service-account-token
      EOF

              # ── Combined apps.yaml ──
              cat $out/02i-forgejo-namespace.yaml > $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/03-forgejo.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/03a-forgejo-shared-storage-ceph-pvc.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/03b-forgejo-db-storageclass-patch.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/04-forgejo-runner-secret.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              if [ -f "$out/04-forgejo-actions.yaml" ]; then
                cat $out/04-forgejo-actions.yaml >> $out/apps.yaml
                echo "---" >> $out/apps.yaml
              fi
              cat $out/04-argocd-forgejo-repo.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/02g-edukurs-cnpg-scheduled-backup.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/02h-forgejo-cnpg-scheduled-backup.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/10-verdaccio-namespace.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/10a-verdaccio-pvc.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/13-verdaccio-argocd-app.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/11-minecraft-namespace.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/14-minecraft-argocd-app.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/15-edukurs-namespace.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/15-batllavatourist-namespace.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/15-quadpacienti-namespace.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/16-edukurs-argocd-app.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/16-batllavatourist-argocd-app.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/16-quadpacienti-argocd-app.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/17-openclaw-namespace.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/17a-openclaw-pvc.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/17b-openclaw-configmap.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/17c-openclaw-deployment.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/17d-openclaw-service.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/17e-openclaw-ingress.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/18-orkestr-namespace.yaml >> $out/apps.yaml
              echo "---" >> $out/apps.yaml
              cat $out/18a-orkestr-ci-rbac.yaml >> $out/apps.yaml
    '';
in {
  config.flake.bootstrapApps = forAllSystems bootstrapAppsFor;
}
