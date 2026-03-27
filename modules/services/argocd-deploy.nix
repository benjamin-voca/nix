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

          echo "Waiting for ingress-nginx controller to be ready..."
          until $kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; do
            echo "Waiting for ingress-nginx controller..."
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
             --set configs.cm.url=http://argocd.quadtech.dev \
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
             --set server.ingress.enabled=false \
              --wait --timeout 5m || true

          echo "Waiting for ingress-nginx admission webhook to be ready..."
          for i in $(seq 1 30); do
            if $kubectl get validatingwebhookconfigurations.admissionregistration.k8s.io ingress-nginx-admission -o jsonpath='{.webhooks[0].clientConfig.url}' 2>/dev/null | grep -q "admission"; then
              echo "Ingress-nginx webhook is ready"
              break
            fi
            echo "Waiting for ingress-nginx webhook... ($i/30)"
            sleep 2
          done

          echo "Creating ArgoCD ingress..."
          if ! $kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "512m"
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
              number: 80
EOF
          then
            echo "Warning: Failed to create ingress, skipping..."
          fi

          echo "Waiting for ArgoCD CRDs to be ready..."
          for i in $(seq 1 30); do
            if $kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
              echo "ArgoCD CRDs are ready"
              break
            fi
            echo "Waiting for ArgoCD CRDs... ($i/30)"
            sleep 2
          done

          echo "Creating ArgoCD Gitea credentials secret..."
          if [ -f /run/secrets/argocd-gitea-username ] && [ -f /run/secrets/argocd-gitea-token ]; then
            GITEA_USERNAME=$(cat /run/secrets/argocd-gitea-username)
            GITEA_TOKEN=$(cat /run/secrets/argocd-gitea-token)
            $kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gitea-quadtech-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
type: Opaque
stringData:
  url: https://gitea.quadtech.dev/QuadCoreTech
  username: "$GITEA_USERNAME"
  password: "$GITEA_TOKEN"
EOF
          else
            echo "Warning: Gitea credentials not found in /run/secrets/, skipping..."
            echo "Add argocd-gitea-username and argocd-gitea-token to secrets/backbone-01.yaml"
          fi
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
