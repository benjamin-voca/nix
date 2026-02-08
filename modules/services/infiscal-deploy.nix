{ config, lib, pkgs, ... }:

let
  cfg = config.services.quadnix.infisical-deploy;
in
{
  options.services.quadnix.infisical-deploy = {
    enable = lib.mkEnableOption "Deploy Infisical to Kubernetes";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "infisical-deploy";
        text = ''
          #!/bin/bash
          set -e
          kubectl="${pkgs.kubectl}/bin/kubectl"

          echo "Waiting for Kubernetes API..."
          until $kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; do
            echo "Waiting for Kubernetes API..."
            sleep 5
          done

           echo "Cleaning up any existing Infisical installation..."
           ${pkgs.kubernetes-helm}/bin/helm uninstall infisical -n infisical --ignore-not-found 2>/dev/null || true
           $kubectl delete ingress infisical -n infisical --ignore-not-found 2>/dev/null || true
           $kubectl delete ingress infisical-ingress -n default --ignore-not-found 2>/dev/null || true
           $kubectl delete secret infisical-secrets -n default --ignore-not-found 2>/dev/null || true
           $kubectl delete secret infisical-secrets -n infisical --ignore-not-found 2>/dev/null || true

          echo "Creating Infisical namespace..."
          $kubectl create namespace infisical --dry-run=client -o yaml | $kubectl apply -f - || true

          echo "Adding Infisical helm repo..."
          ${pkgs.kubernetes-helm}/bin/helm repo add infisical https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts --force-update 2>/dev/null || true
          ${pkgs.kubernetes-helm}/bin/helm repo update

          echo "Deploying Infisical..."
            DB_PASSWORD=$(cat /run/secrets/infisical-db-password)
           ENCRYPTION_KEY=$(cat /run/secrets/infisical-encryption-key)
           AUTH_SECRET=$(cat /run/secrets/infisical-auth-secret)

            ${pkgs.kubernetes-helm}/bin/helm upgrade --install infisical infisical/infisical-standalone \
              --namespace infisical \
              --set global.domain=infisical.quadtech.dev \
              --set global.encryptionKey="$ENCRYPTION_KEY" \
              --set global.authJwtSecret="$AUTH_SECRET" \
              --set ingress.enabled=true \
              --set ingress.className=nginx \
              --set ingress.hosts[0].host=infisical.quadtech.dev \
              --set ingress.hosts[0].paths[0].path=/ \
              --set ingress.hosts[0].paths[0].pathType=Prefix \
              --wait --timeout 5m || true

            $kubectl create secret generic infisical-secrets \
              --from-literal=DB_PASSWORD="$DB_PASSWORD" \
              --from-literal=ENCRYPTION_KEY="$ENCRYPTION_KEY" \
              --from-literal=AUTH_SECRET="$AUTH_SECRET" \
              -n infisical || true

          echo "Infisical deployed successfully!"
          echo "URL: https://infiscal.quadtech.dev"
        '';
      })
      (pkgs.writeShellApplication {
        name = "infisical-cleanup";
        text = ''
          #!/bin/bash
          set -e
          export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

          kubectl="${pkgs.kubectl}/bin/kubectl"

          $kubectl delete ingress infisical -n infisical --ignore-not-found 2>/dev/null || true
          ${pkgs.kubernetes-helm}/bin/helm uninstall infisical -n infisical --ignore-not-found 2>/dev/null || true
        '';
      })
      pkgs.kubectl
    ];

    systemd.services.infisical-deploy = {
      description = "Deploy Infisical to Kubernetes";
      after = [ "network-online.target" "kube-apiserver.service" ];
      wants = [ "network-online.target" "kube-apiserver.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/sw/bin/infisical-deploy";
        ExecStop = "/run/current-system/sw/bin/infisical-cleanup";
      };
    };
  };
}