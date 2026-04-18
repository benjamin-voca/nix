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
          for ns in harbor cnpg-system edukurs forgejo quadpacient minecraft erpnext openclaw quadpacienti rook-ceph orkestr; do
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
            HARBOR_REG_USER="harbor_registry_user"
            HARBOR_REG_PW=$(cat /run/secrets/harbor-registry-password)

            CURRENT_REGISTRY_PW=""
            if $kubectl -n harbor get secret harbor-registry-secret >/dev/null 2>&1; then
              CURRENT_REGISTRY_PW=$($kubectl -n harbor get secret harbor-registry-secret -o jsonpath='{.data.REGISTRY_PASSWD}' 2>/dev/null | base64 -d || true)
            fi

            if [ "$CURRENT_REGISTRY_PW" = "$HARBOR_REG_PW" ] && \
               $kubectl -n harbor get secret harbor-registry-secret -o jsonpath='{.data.REGISTRY_HTPASSWD}' >/dev/null 2>&1; then
              echo "Harbor registry credentials already up to date"
            else
              HARBOR_REG_HTPASSWD=$(${pkgs.apacheHttpd}/bin/htpasswd -nbBC 10 "$HARBOR_REG_USER" "$HARBOR_REG_PW" | tr -d '\n')
              $kubectl create secret generic harbor-registry-secret \
                --namespace=harbor \
                --from-literal=password="$HARBOR_REG_PW" \
                --from-literal=REGISTRY_PASSWD="$HARBOR_REG_PW" \
                --from-literal=REGISTRY_HTPASSWD="$HARBOR_REG_HTPASSWD" \
                --dry-run=client -o yaml | $kubectl apply -f -
              $kubectl -n harbor rollout restart deployment/harbor-core deployment/harbor-jobservice deployment/harbor-registry || true
              echo "Injected harbor-registry-secret (Harbor chart compatible keys)"
            fi
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

          # Forgejo database bootstrap secret (CNPG initdb)
          if [ -f /run/secrets/forgejo-db-password ]; then
            FORGEJO_DB_PW=$(cat /run/secrets/forgejo-db-password)
            $kubectl create secret generic forgejo-db \
              --namespace=forgejo \
              --type=kubernetes.io/basic-auth \
              --from-literal=username=forgejo \
              --from-literal=password="$FORGEJO_DB_PW" \
              --from-literal=dbname=forgejo \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected forgejo-db secret"
          fi

          # Forgejo admin credentials
          if [ -f /run/secrets/forgejo-admin-password ]; then
            FORGEJO_ADMIN_PW=$(cat /run/secrets/forgejo-admin-password)
            $kubectl create secret generic forgejo-admin \
              --namespace=forgejo \
              --from-literal=username=forgejo_admin \
              --from-literal=password="$FORGEJO_ADMIN_PW" \
              --from-literal=email=admin@quadtech.dev \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected forgejo-admin secret"
          fi

          # Forgejo Actions runner registration token
          if [ -f /run/secrets/forgejo-runner-token ]; then
            FORGEJO_RUNNER_TOKEN=$(cat /run/secrets/forgejo-runner-token)
            $kubectl create secret generic forgejo-runner-token \
              --namespace=forgejo \
              --from-literal=token="$FORGEJO_RUNNER_TOKEN" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected forgejo-runner-token secret"
          fi

          # Keep forgejo-runner-token refreshed from live Forgejo instance
          FORGEJO_DEPLOY=""
          if $kubectl -n forgejo get deploy forgejo >/dev/null 2>&1; then
            FORGEJO_DEPLOY="forgejo"
          fi

          if [ -n "$FORGEJO_DEPLOY" ]; then
            if RUNNER_TOKEN=$($kubectl -n forgejo exec "deploy/$FORGEJO_DEPLOY" -c gitea -- sh -c "APP_INI=\"\"; if [ -f /data/gitea/conf/app.ini ]; then APP_INI=/data/gitea/conf/app.ini; elif [ -f /data/forgejo/conf/app.ini ]; then APP_INI=/data/forgejo/conf/app.ini; fi; [ -n \"\$APP_INI\" ] && su-exec git /usr/local/bin/gitea --config \"\$APP_INI\" actions generate-runner-token" 2>/dev/null); then
              if [ -n "$RUNNER_TOKEN" ]; then
                $kubectl create secret generic forgejo-runner-token \
                  --namespace=forgejo \
                  --from-literal=token="$RUNNER_TOKEN" \
                  --dry-run=client -o yaml | $kubectl apply -f -
                echo "Refreshed forgejo-runner-token from Forgejo"
              fi
            fi
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
            for target_ns in cnpg-system edukurs forgejo quadpacient orkestr; do
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
            if [ -f /run/secrets/forgejo-agent-token ]; then
              OC_FORGEJO_AGENT_TOKEN=$(cat /run/secrets/forgejo-agent-token)
              OC_ARGS="$OC_ARGS --from-literal=FORGEJO_AGENT_TOKEN=$OC_FORGEJO_AGENT_TOKEN"
            fi
            # shellcheck disable=SC2086
            $kubectl create secret generic openclaw-secrets \
              --namespace=openclaw \
              $OC_ARGS \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected openclaw-secrets"
          fi

          # Orkestr secrets
          if [ -f /run/secrets/orkestr-db-password ]; then
            ORKESTR_DB_PW=$(cat /run/secrets/orkestr-db-password)
            $kubectl create secret generic orkestr-db-secret \
              --namespace=orkestr \
              --type=kubernetes.io/basic-auth \
              --from-literal=username=orkestr \
              --from-literal=password="$ORKESTR_DB_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected orkestr-db-secret"
          fi

          if [ -f /run/secrets/orkestr-db-password ] && [ -f /run/secrets/orkestr-secret-key-base ] && [ -f /run/secrets/orkestr-token-signing-secret ] && [ -f /run/secrets/orkestr-electric-secret ]; then
            ORKESTR_DB_PW=$(cat /run/secrets/orkestr-db-password)
            ORKESTR_SKB=$(cat /run/secrets/orkestr-secret-key-base)
            ORKESTR_TSS=$(cat /run/secrets/orkestr-token-signing-secret)
            ORKESTR_ES=$(cat /run/secrets/orkestr-electric-secret)
            $kubectl create secret generic orkestr-app-secrets \
              --namespace=orkestr \
              --from-literal=DATABASE_URL="postgresql://orkestr:$ORKESTR_DB_PW@orkestr-db-rw.orkestr.svc.cluster.local:5432/orkestr?sslmode=disable" \
              --from-literal=SECRET_KEY_BASE="$ORKESTR_SKB" \
              --from-literal=TOKEN_SIGNING_SECRET="$ORKESTR_TSS" \
              --from-literal=PHX_SERVER="true" \
              --from-literal=PHX_HOST="app.orkestr-os.com" \
              --from-literal=PORT="4000" \
              --from-literal=ELECTRIC_SYNC_ENABLED="true" \
              --from-literal=ELECTRIC_URL="http://orkestr-electric-proxy.orkestr.svc.cluster.local/v1/shape" \
              --from-literal=ELECTRIC_SECRET="$ORKESTR_ES" \
              --from-literal=ELECTRIC_UPSTREAM_TIMEOUT="70000" \
              --from-literal=OTEL_EXPORTER_OTLP_ENDPOINT="http://tempo.tempo.svc.cluster.local:4318" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected orkestr-app-secrets"

            $kubectl create secret generic orkestr-electric-secrets \
              --namespace=orkestr \
              --from-literal=DATABASE_URL="postgresql://orkestr:$ORKESTR_DB_PW@orkestr-db-rw.orkestr.svc.cluster.local:5432/orkestr?sslmode=disable" \
              --from-literal=ELECTRIC_SECRET="$ORKESTR_ES" \
              --from-literal=ELECTRIC_INSECURE="false" \
              --from-literal=ELECTRIC_LOG_LEVEL="info" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected orkestr-electric-secrets"
          fi

          # Harbor docker config for orkestr namespace
          if [ -f /run/secrets/harbor-registry-password ]; then
            HARBOR_REG_PW=$(cat /run/secrets/harbor-registry-password)
            $kubectl create secret docker-registry harbor-registry \
              --namespace=orkestr \
              --docker-server=10.0.0.56:5000 \
              --docker-username=harbor_registry_user \
              --docker-password="$HARBOR_REG_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected harbor-registry (orkestr namespace)"
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
