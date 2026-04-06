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
            ${pkgs.kubernetes-helm}/bin/helm uninstall infisical -n default --ignore-not-found 2>/dev/null || true
            $kubectl delete ingress infisical -n infisical --ignore-not-found 2>/dev/null || true
            $kubectl delete ingress infisical-ingress -n default --ignore-not-found 2>/dev/null || true
            $kubectl delete secret infisical-secrets -n default --ignore-not-found 2>/dev/null || true
            $kubectl delete secret infisical-secrets -n infisical --ignore-not-found 2>/dev/null || true
            $kubectl delete all -l app.kubernetes.io/instance=infisical -n default --ignore-not-found 2>/dev/null || true
            $kubectl delete deployment infisical-infisical-standalone-infisical -n default --ignore-not-found 2>/dev/null || true
            $kubectl delete service infisical-infisical-standalone-infisical -n default --ignore-not-found 2>/dev/null || true
            $kubectl delete job infisical-schema-migration-1 -n default --ignore-not-found 2>/dev/null || true
            $kubectl delete pods -n default -l app.kubernetes.io/instance=infisical --ignore-not-found 2>/dev/null || true

          echo "Creating Infisical namespace..."
          $kubectl create namespace infisical --dry-run=client -o yaml | $kubectl apply -f - || true

          echo "Adding Infisical helm repo..."
          ${pkgs.kubernetes-helm}/bin/helm repo add infisical https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts --force-update 2>/dev/null || true
          ${pkgs.kubernetes-helm}/bin/helm repo update

          echo "Deploying Infisical..."
            DB_PASSWORD=$(cat /run/secrets/infisical-db-password)
            RAW_ENCRYPTION_KEY=$(cat /run/secrets/infisical-encryption-key)
            ENCRYPTION_KEY=$(printf '%s' "$RAW_ENCRYPTION_KEY" | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -c1-32)
            AUTH_SECRET=$(cat /run/secrets/infisical-auth-secret)

            echo "Ensuring infisical DB and app secrets exist in infisical namespace..."
            $kubectl delete cluster.postgresql.cnpg.io infisical-db -n infisical --ignore-not-found 2>/dev/null || true
            $kubectl delete pod infisical-db-1 -n infisical --ignore-not-found 2>/dev/null || true
            $kubectl delete pvc infisical-db-1 -n infisical --ignore-not-found 2>/dev/null || true

            $kubectl create secret generic infisical-db \
              --namespace infisical \
              --type kubernetes.io/basic-auth \
              --from-literal=username=infisical \
              --from-literal=password="$DB_PASSWORD" \
              --from-literal=dbname=infisical \
              --dry-run=client -o yaml | $kubectl apply -f -

            $kubectl create secret generic infisical-secrets \
              --namespace infisical \
              --from-literal=DB_CONNECTION_URI="postgresql://infisical:$DB_PASSWORD@infisical-db-ceph-rw.infisical.svc.cluster.local:5432/infisical" \
              --from-literal=REDIS_URL="" \
              --from-literal=ENCRYPTION_KEY="$ENCRYPTION_KEY" \
              --from-literal=AUTH_SECRET="$AUTH_SECRET" \
              --from-literal=SITE_URL="https://infisical.quadtech.dev" \
              --dry-run=client -o yaml | $kubectl apply -f -

            echo "Applying declarative CNPG cluster for Infisical..."
            $kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: infisical-db-ceph
  namespace: infisical
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie
  instances: 1
  storage:
    storageClass: ceph-block
    size: 10Gi
  bootstrap:
    initdb:
      database: infisical
      owner: infisical
      secret:
        name: infisical-db
EOF

            ${pkgs.kubernetes-helm}/bin/helm upgrade --install infisical infisical/infisical-standalone \
              --namespace infisical \
              --version 1.7.2 \
              --set infisical.image.tag=v0.158.7 \
              --set infisical.replicaCount=1 \
              --set infisical.resources.requests.cpu=100m \
              --set infisical.resources.requests.memory=256Mi \
              --set infisical.resources.limits.memory=2Gi \
              --set infisical.kubeSecretRef=infisical-secrets \
              --set ingress.enabled=true \
              --set ingress.hostName=infisical.quadtech.dev \
              --set ingress.ingressClassName=nginx \
              --set ingress.nginx.enabled=false \
              --set postgresql.enabled=false \
              --set postgresql.useExistingPostgresSecret.enabled=true \
              --set postgresql.useExistingPostgresSecret.existingConnectionStringSecret.name=infisical-secrets \
              --set postgresql.useExistingPostgresSecret.existingConnectionStringSecret.key=DB_CONNECTION_URI \
              --set redis.enabled=true \
              --wait --timeout 20m || true

          echo "Infisical deployed successfully!"
          echo "URL: https://infisical.quadtech.dev"
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
