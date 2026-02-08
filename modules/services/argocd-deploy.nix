{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.quadnix.argocd-deploy;
  system = pkgs.stdenv.system;
  helmLib = import "${inputs.self}/lib/helm" {
    inherit (inputs) nixhelm nix-kube-generators;
    inherit pkgs system;
  };
  chart = helmLib.buildChart {
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
    };
  };
in
{
  options.services.quadnix.argocd-deploy = {
    enable = lib.mkEnableOption "Deploy ArgoCD to Kubernetes via Helm";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "argocd-deploy";
        text = ''
          # shellcheck disable=SC2016
          #!/bin/bash
          set -e
          export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

          kubectl="${pkgs.kubectl}/bin/kubectl"

          echo "Waiting for Kubernetes API..."
          until $kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; do
            echo "Waiting for Kubernetes API..."
            sleep 5
          done

          echo "Cleaning up any existing ArgoCD installation..."
          ${pkgs.kubernetes-helm}/bin/helm uninstall argocd -n argocd --ignore-not-found 2>/dev/null || true
          $kubectl delete ingress argocd-server -n argocd --ignore-not-found 2>/dev/null || true

          echo "Cleaning up ArgoCD CRDs and cluster resources..."
          $kubectl delete crd applications.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete crd appprojects.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete crd applicationsets.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrole argocd-application-controller --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrole argocd-server --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrolebinding argocd-application-controller --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrolebinding argocd-server --ignore-not-found 2>/dev/null || true

          echo "Creating ArgoCD namespace..."
          $kubectl create namespace argocd --dry-run=client -o yaml | $kubectl apply -f - || true

          echo "Adding ArgoCD helm repo..."
          ${pkgs.kubernetes-helm}/bin/helm repo add argoproj https://argoproj.github.io/argo-helm --force-update 2>/dev/null || true
          ${pkgs.kubernetes-helm}/bin/helm repo update

          echo "Deploying ArgoCD..."
          PASSWORD=$(cat /run/secrets/argocd-admin-password)
          ${pkgs.kubernetes-helm}/bin/helm upgrade --install argocd argoproj/argo-cd \
            --namespace argocd \
            --version 5.46.0 \
            --set global.domain=argocd.quadtech.dev \
            --set configs.cm.'server\.insecure'=true \
            --set configs.cm.url=https://argocd.quadtech.dev \
            --set configs.params.'server\.insecure'=true \
            --set configs.secret.argocdServerAdminPassword="$PASSWORD" \
            --set server.replicas=1 \
            --set server.service.type=ClusterIP \
            --set redis.enabled=true \
            --set redis-ha.enabled=false \
            --set controller.replicas=1 \
            --set repoServer.replicas=1 \
            --set applicationSet.enabled=true \
            --set notifications.enabled=true \
            --set global.image.tag=v2.9.3 \
             --set server.ingress.enabled=true \
             --set server.ingress.className=nginx \
             --set server.ingress.hosts[0]=argocd.quadtech.dev \
             --wait --timeout 5m || true

          echo "Creating ArgoCD ingress..."
          $kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.quadtech.dev
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
EOF

          echo "ArgoCD deployed successfully!"
          echo "URL: https://argocd.quadtech.dev"
          echo "Admin username: admin"
          echo "Admin password: admin"
        '';
      })
      (pkgs.writeShellApplication {
        name = "argocd-cleanup";
        text = ''
          #!/bin/bash
          set -e
          export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

          kubectl="${pkgs.kubectl}/bin/kubectl"

          $kubectl delete ingress argocd-server -n argocd --ignore-not-found 2>/dev/null || true
          $kubectl delete -f ${chart} --ignore-not-found 2>/dev/null || true
          $kubectl delete crd applications.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete crd appprojects.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete crd applicationsets.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrole argocd-application-controller --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrole argocd-server --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrolebinding argocd-application-controller --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrolebinding argocd-server --ignore-not-found 2>/dev/null || true
        '';
      })
      pkgs.kubectl
    ];

    systemd.services.argocd-deploy = {
      description = "Deploy ArgoCD to Kubernetes";
      after = [ "network-online.target" "kube-apiserver.service" ];
      wants = [ "network-online.target" "kube-apiserver.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/sw/bin/argocd-deploy";
        ExecStop = "/run/current-system/sw/bin/argocd-cleanup";
      };
    };
  };
}
