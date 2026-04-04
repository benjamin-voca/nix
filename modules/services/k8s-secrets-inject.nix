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
          for ns in harbor cnpg-system edukurs gitea quadpacient minecraft erpnext openclaw quadpacienti rook-ceph; do
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

          # Gitea database password
          if [ -f /run/secrets/gitea-db-password ]; then
            GITEA_DB_PW=$(cat /run/secrets/gitea-db-password)
            $kubectl create secret generic gitea-db \
              --namespace=gitea \
              --type=kubernetes.io/basic-auth \
              --from-literal=username=gitea \
              --from-literal=password="$GITEA_DB_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected gitea-db secret"
          fi

          # Gitea Actions runner registration token
          if [ -f /run/secrets/gitea-runner-token ]; then
            GITEA_RUNNER_TOKEN=$(cat /run/secrets/gitea-runner-token)
            $kubectl create secret generic gitea-runner-token \
              --namespace=gitea \
              --from-literal=token="$GITEA_RUNNER_TOKEN" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected gitea-runner-token secret"
          fi

          # Ceph RGW S3 credentials for CNPG backups
          S3_ACCESS_KEY=""
          S3_SECRET_KEY=""

          if $kubectl -n rook-ceph get secret rook-ceph-object-user-ceph-objectstore-cnpg-backups >/dev/null 2>&1; then
            S3_ACCESS_KEY=$($kubectl -n rook-ceph get secret rook-ceph-object-user-ceph-objectstore-cnpg-backups -o jsonpath='{.data.AccessKey}' | base64 -d)
            S3_SECRET_KEY=$($kubectl -n rook-ceph get secret rook-ceph-object-user-ceph-objectstore-cnpg-backups -o jsonpath='{.data.SecretKey}' | base64 -d)
          elif [ -f /run/secrets/ceph-rgw-s3-access-key ] && [ -f /run/secrets/ceph-rgw-s3-secret-key ]; then
            S3_ACCESS_KEY=$(cat /run/secrets/ceph-rgw-s3-access-key)
            S3_SECRET_KEY=$(cat /run/secrets/ceph-rgw-s3-secret-key)
          fi

          if [ -n "$S3_ACCESS_KEY" ] && [ -n "$S3_SECRET_KEY" ]; then
            for target_ns in cnpg-system edukurs gitea quadpacient; do
              $kubectl create secret generic ceph-rgw-s3-credentials \
                --namespace="$target_ns" \
                --from-literal=ACCESS_KEY_ID="$S3_ACCESS_KEY" \
                --from-literal=ACCESS_SECRET_KEY="$S3_SECRET_KEY" \
                --from-literal=ACCESS_REGION="us-east-1" \
                --dry-run=client -o yaml | $kubectl apply -f -
              echo "Injected ceph-rgw-s3-credentials in $target_ns"
            done
          fi

          # Keep app DB URLs pinned to Ceph CNPG services
          if $kubectl -n edukurs get secret edukurs-app-secrets >/dev/null 2>&1 && \
             $kubectl -n edukurs get secret edukurs-db-ceph-secret >/dev/null 2>&1; then
            EDUKURS_DB_USER=$($kubectl -n edukurs get secret edukurs-db-ceph-secret -o jsonpath='{.data.username}' | base64 -d)
            EDUKURS_DB_PASS=$($kubectl -n edukurs get secret edukurs-db-ceph-secret -o jsonpath='{.data.password}' | base64 -d)
            EDUKURS_DB_URL="postgresql://$EDUKURS_DB_USER:$EDUKURS_DB_PASS@edukurs-db-ceph-rw.edukurs.svc.cluster.local:5432/mydatabase"
            EDUKURS_DB_URL_B64=$(printf '%s' "$EDUKURS_DB_URL" | base64 | tr -d '\n')
            $kubectl -n edukurs patch secret edukurs-app-secrets --type merge \
              -p "{\"data\":{\"POSTGRES_URL\":\"$EDUKURS_DB_URL_B64\"}}"
            echo "Pinned edukurs-app-secrets POSTGRES_URL to Ceph"
          fi

          if $kubectl -n quadpacient get secret quadpacient-app-secrets >/dev/null 2>&1 && \
             $kubectl -n quadpacient get secret quadpacient-db-ceph-secret >/dev/null 2>&1; then
            QUADPACIENT_DB_USER=$($kubectl -n quadpacient get secret quadpacient-db-ceph-secret -o jsonpath='{.data.username}' | base64 -d)
            QUADPACIENT_DB_PASS=$($kubectl -n quadpacient get secret quadpacient-db-ceph-secret -o jsonpath='{.data.password}' | base64 -d)
            QUADPACIENT_DB_URL="postgresql://$QUADPACIENT_DB_USER:$QUADPACIENT_DB_PASS@quadpacient-db-ceph-rw.quadpacient.svc.cluster.local:5432/quadpacient"
            QUADPACIENT_DB_URL_B64=$(printf '%s' "$QUADPACIENT_DB_URL" | base64 | tr -d '\n')
            $kubectl -n quadpacient patch secret quadpacient-app-secrets --type merge \
              -p "{\"data\":{\"POSTGRES_URL\":\"$QUADPACIENT_DB_URL_B64\"}}"
            echo "Pinned quadpacient-app-secrets POSTGRES_URL to Ceph"
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

            $kubectl create secret generic erpnext-mariadb-auth \
              --namespace=erpnext \
              --from-literal=mariadb-root-password="$ERPNEXT_DB_PW" \
              --from-literal=mariadb-password="$ERPNEXT_DB_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected erpnext-mariadb-auth secret"
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
            if [ -f /run/secrets/openclaw-discord-id ]; then
              OC_DISCORD_BOT_TOKEN=$(cat /run/secrets/openclaw-discord-id)
              OC_ARGS="$OC_ARGS --from-literal=DISCORD_BOT_TOKEN=$OC_DISCORD_BOT_TOKEN"
            fi
            if [ -f /run/secrets/openclaw-server-id ]; then
              OC_DISCORD_SERVER_ID=$(cat /run/secrets/openclaw-server-id)
              OC_ARGS="$OC_ARGS --from-literal=OPENCLAW_DISCORD_SERVER_ID=$OC_DISCORD_SERVER_ID"
            fi
            if [ -f /run/secrets/openclaw-beni-discord-id ]; then
              OC_BENI_DISCORD_ID=$(cat /run/secrets/openclaw-beni-discord-id)
              OC_ARGS="$OC_ARGS --from-literal=OPENCLAW_BENI_DISCORD_ID=$OC_BENI_DISCORD_ID"
            fi
            if [ -f /run/secrets/gitea-agent-token ]; then
              OC_GITEA_AGENT_TOKEN=$(cat /run/secrets/gitea-agent-token)
              OC_ARGS="$OC_ARGS --from-literal=GITEA_AGENT_TOKEN=$OC_GITEA_AGENT_TOKEN"
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
