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
                  argocdServerAdminPassword = "$2a$10$bX.6MmE5x1n.KlTA./3ax.xXzgP5CzLu1CyFyvMnEeh.vN9tDVVLC";
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
            name: longhorn-system
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: harbor
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: verdaccio
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: erpnext

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

          # Verdaccio PVC
          ---
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
                - name: controller.service.annotations.external-dns\.alpha\.kubernetes.io/hostname
                  value: "*.quadtech.dev"
                - name: controller.publishService.enabled
                  value: "true"
            destination:
              server: https://kubernetes.default.svc
              namespace: ingress-nginx
            syncPolicy:
              automated:
                prune: true
                selfHeal: true

          # ArgoCD Application - Longhorn
          ---
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: longhorn
            namespace: argocd
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
            destination:
              server: https://kubernetes.default.svc
              namespace: harbor
            syncPolicy:
              automated:
                prune: true
                selfHeal: true

          # ArgoCD Application - Verdaccio
          ---
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: verdaccio
            namespace: argocd
          spec:
            ignoreDifferences:
            - group: networking.k8s.io
              kind: Ingress
              jsonPointers:
              - /metadata/annotations
            project: default
            source:
              chart: verdaccio
              repoURL: https://charts.verdaccio.org
              targetRevision: 4.29.0
              helm:
                parameters:
                - name: ingress.annotations nginx\.ingress\.kubernetes\.io/ssl-redirect
                  value: "false"
                - name: ingress.annotations nginx\.ingress\.kubernetes\.io/backend-protocol
                  value: HTTP
                - name: ingress.tls
                  value: "true"
            destination:
              server: https://kubernetes.default.svc
              namespace: verdaccio
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
            storageClassName: longhorn
            resources:
              requests:
                storage: 20Gi

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
                parameters:
                - name: ingress.annotations nginx\.ingress\.kubernetes\.io/ssl-redirect
                  value: "false"
                - name: ingress.annotations nginx\.ingress\.kubernetes\.io/backend-protocol
                  value: HTTP
                - name: ingress.enabled
                  value: "true"
                - name: ingress.className
                  value: nginx
                - name: ingress.hosts[0]
                  value: helpdesk.quadtech.dev
                - name: ingress.tls[0].hosts[0]
                  value: helpdesk.quadtech.dev
                - name: ingress.tls[0].secretName
                  value: helpdesk-quadtech-dev-tls
                - name: persistence.enabled
                  value: "true"
                - name: persistence.storageClass
                  value: longhorn
                - name: persistence.size
                  value: 20Gi
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
