{ config, lib, pkgs, ... }:

let
  cfg = config.services.quadnix.k8s-secrets-inject;
in
{
  options.services.quadnix.k8s-secrets-inject = {
    enable = lib.mkEnableOption "Inject SOPS secrets into Kubernetes";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "k8s-secrets-inject";
        text = ''
          #!/bin/bash
          export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig
          kubectl="${pkgs.kubectl}/bin/kubectl"

          echo "Waiting for Kubernetes API..."
          until $kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; do
            echo "Waiting for Kubernetes API..."
            sleep 5
          done

          # Ensure namespaces exist before injecting secrets
          for ns in harbor cnpg-system minecraft erpnext openclaw quadpacienti; do
            $kubectl create namespace "$ns" --dry-run=client -o yaml | $kubectl apply -f - 2>/dev/null || true
          done

          # Harbor admin password
          if [ -f /run/secrets/harbor-admin-password ]; then
            HARBOR_ADMIN_PW=$(cat /run/secrets/harbor-admin-password)
            $kubectl create secret generic harbor-admin-secret \
              --namespace=harbor \
              --from-literal=password="$HARBOR_ADMIN_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected harbor-admin-secret"
          fi

          # Harbor registry password
          if [ -f /run/secrets/harbor-registry-password ]; then
            HARBOR_REG_PW=$(cat /run/secrets/harbor-registry-password)
            $kubectl create secret generic harbor-registry-secret \
              --namespace=harbor \
              --from-literal=password="$HARBOR_REG_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected harbor-registry-secret"
          fi

          # Harbor docker config for quadpacienti namespace
          if [ -f /run/secrets/harbor-admin-password ]; then
            HARBOR_PW=$(cat /run/secrets/harbor-admin-password)
            $kubectl create secret docker-registry harbor-registry \
              --namespace=quadpacienti \
              --docker-server=harbor.quadtech.dev \
              --docker-username=admin \
              --docker-password="$HARBOR_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected harbor-registry (quadpacienti namespace)"
          fi

          # CNPG edukurs password
          if [ -f /run/secrets/cnpg-edukurs-password ]; then
            CNPG_PW=$(cat /run/secrets/cnpg-edukurs-password)
            $kubectl create secret generic shared-pg-app \
              --namespace=cnpg-system \
              --from-literal=username=edukurs \
              --from-literal=password="$CNPG_PW" \
              --from-literal=dbname=edukurs \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected shared-pg-app secret"
          fi

          # Minecraft RCON password
          if [ -f /run/secrets/minecraft-rcon-password ]; then
            MC_RCON=$(cat /run/secrets/minecraft-rcon-password)
            $kubectl create secret generic minecraft-rcon-secret \
              --namespace=minecraft \
              --from-literal=rcon-password="$MC_RCON" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected minecraft-rcon-secret"
          fi

          # ERPNext DB admin password
          if [ -f /run/secrets/erpnext-db-admin-password ]; then
            ERPNEXT_DB_PW=$(cat /run/secrets/erpnext-db-admin-password)
            $kubectl create secret generic erpnext-db-admin \
              --namespace=erpnext \
              --from-literal=password="$ERPNEXT_DB_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected erpnext-db-admin secret"
          fi

          # ERPNext admin password
          if [ -f /run/secrets/erpnext-admin-password ]; then
            ERPNEXT_ADMIN_PW=$(cat /run/secrets/erpnext-admin-password)
            $kubectl create secret generic erpnext-admin \
              --namespace=erpnext \
              --from-literal=password="$ERPNEXT_ADMIN_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected erpnext-admin secret"
          fi

          # OpenClaw secrets
          if [ -f /run/secrets/openclaw-gateway-token ]; then
            OC_TOKEN=$(cat /run/secrets/openclaw-gateway-token)
            OC_ARGS="--from-literal=OPENCLAW_GATEWAY_TOKEN=$OC_TOKEN"
            if [ -f /run/secrets/openclaw-gateway-password ]; then
              OC_PASSWORD=$(cat /run/secrets/openclaw-gateway-password)
              OC_ARGS="$OC_ARGS --from-literal=OPENCLAW_GATEWAY_PASSWORD=$OC_PASSWORD"
            fi
            if [ -f /run/secrets/openclaw-minimax-api-key ]; then
              OC_API_KEY=$(cat /run/secrets/openclaw-minimax-api-key)
              OC_ARGS="$OC_ARGS --from-literal=MINIMAX_API_KEY=$OC_API_KEY"
            fi
            # shellcheck disable=SC2086
            $kubectl create secret generic openclaw-secrets \
              --namespace=openclaw \
              $OC_ARGS \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected openclaw-secrets"
          fi

          echo "K8s secrets injection complete."
        '';
      })
      pkgs.kubectl
    ];

    systemd.services.k8s-secrets-inject = {
      description = "Inject SOPS secrets into Kubernetes";
      after = [ "network-online.target" "kube-apiserver.service" ];
      wants = [ "network-online.target" "kube-apiserver.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/sw/bin/k8s-secrets-inject";
      };
    };
  };
}
