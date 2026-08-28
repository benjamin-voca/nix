{
  config,
  lib,
  pkgs,
  ...
}: let
  d = import ../../lib/domain.nix;
  cfg = config.services.quadnix.k8s-secrets-inject;
in {
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
          for ns in harbor cnpg-system edukurs forgejo minecraft openclaw rook-ceph orkestr argocd mosaic clickstack n8n kaneo; do
            $kubectl create namespace "$ns" --dry-run=client -o yaml | $kubectl apply -f - 2>/dev/null || true
          done

          # ArgoCD admin password (bcrypt hash from sops)
          if [ -f /run/secrets/argocd-admin-password ]; then
            ARGOCD_ADMIN_PW=$(cat /run/secrets/argocd-admin-password)
            $kubectl patch secret argocd-secret -n argocd -p "{\"stringData\":{\"admin.password\":\"$ARGOCD_ADMIN_PW\"}}" 2>/dev/null || true
            echo "Injected argocd admin password"
          fi

          # ArgoCD Forgejo credentials (covers both case variants)
          if [ -f /run/secrets/argocd-forgejo-username ] && [ -f /run/secrets/argocd-forgejo-token ]; then
            FORGEJO_USER=$(cat /run/secrets/argocd-forgejo-username)
            FORGEJO_TOKEN=$(cat /run/secrets/argocd-forgejo-token)
            for URL_VARIANT in "quadtech" "quadcoretech"; do
              ORG_NAME="$URL_VARIANT"
              [ "$URL_VARIANT" = "quadtech" ] && ORG_NAME="QuadCoreTech"
              $kubectl apply -f - <<EOF
          apiVersion: v1
          kind: Secret
          metadata:
            name: forgejo-quadtech-repo-creds-$URL_VARIANT
            namespace: argocd
            labels:
              argocd.argoproj.io/secret-type: repo-creds
          type: Opaque
          stringData:
            url: ${d.url "forge"}/$ORG_NAME
            username: "$FORGEJO_USER"
            password: "$FORGEJO_TOKEN"
          EOF
            done
            echo "Injected forgejo repo creds"
          fi

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

          
          # Harbor pull secret for the forgejo-actions runner.
          # The runner's Docker-in-Docker sidecar pulls private job images
          # (e.g. library/orkestr-ci) via the Go docker SDK in the act-runner
          # container, which reads /root/.docker/config.json for credentials.
          # 10.0.0.56:5000 is the HTTP endpoint the dind daemon is configured to
          # trust (insecure-registry). Without this, pulls fail with
          # "no basic auth credentials" because the `library` project is private.
          if [ -f /run/secrets/harbor-registry-password ]; then
            HARBOR_REG_PW=$(cat /run/secrets/harbor-registry-password)
            $kubectl create secret docker-registry harbor-registry \
              --namespace=forgejo \
              --docker-server=10.0.0.56:5000 \
              --docker-username=harbor_registry_user \
              --docker-password="$HARBOR_REG_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected harbor-registry (forgejo namespace) for act-runner pulls"
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

          # (grafana-db injection removed — standalone grafana namespace wound
          # down; kube-prometheus-stack grafana manages its own admin secret)

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
              --from-literal=email=${d.email "admin"} \
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

          # ClickStack secrets (HyperDX + OTel collector + Mongo + CH users.d)
          # Backed by sops keys: clickstack-otlp-token, clickstack-session-secret,
          # clickstack-ch-app-password, clickstack-ch-collector-password,
          # clickstack-hyperdx-api-key, clickstack-mongo-password
          if [ -f /run/secrets/clickstack-hyperdx-api-key ] \
             && [ -f /run/secrets/clickstack-ch-app-password ] \
             && [ -f /run/secrets/clickstack-ch-collector-password ] \
             && [ -f /run/secrets/clickstack-session-secret ] \
             && [ -f /run/secrets/clickstack-mongo-password ] \
             && [ -f /run/secrets/clickstack-otlp-token ]; then
            HK=$(cat /run/secrets/clickstack-hyperdx-api-key)
            APP_PW=$(cat /run/secrets/clickstack-ch-app-password)
            COLL_PW=$(cat /run/secrets/clickstack-ch-collector-password)
            SESS=$(cat /run/secrets/clickstack-session-secret)
            MONGO_PW=$(cat /run/secrets/clickstack-mongo-password)
            OTLP_TOKEN=$(cat /run/secrets/clickstack-otlp-token)

            # Shared HyperDX + collector env/config secret.
            # DEFAULT_CONNECTIONS / DEFAULT_SOURCES seed the HyperDX UI sources
            # (mirrors the chart defaults, trimmed to Logs/Traces/Metrics).
            DEFAULT_CONNECTIONS='[{"name":"Local ClickHouse","host":"http://clickhouse.clickstack.svc.cluster.local:8123","port":8123,"username":"app","password":"'"$APP_PW"'"}]'
            DEFAULT_SOURCES='[{"from":{"databaseName":"default","tableName":"otel_logs"},"kind":"log","timestampValueExpression":"Timestamp","name":"Logs","displayedTimestampValueExpression":"Timestamp","implicitColumnExpression":"Body","serviceNameExpression":"ServiceName","bodyExpression":"Body","eventAttributesExpression":"LogAttributes","resourceAttributesExpression":"ResourceAttributes","defaultTableSelectExpression":"Timestamp,ServiceName,SeverityText,Body","severityTextExpression":"SeverityText","traceIdExpression":"TraceId","spanIdExpression":"SpanId","connection":"Local ClickHouse","traceSourceId":"Traces","metricSourceId":"Metrics"},{"from":{"databaseName":"default","tableName":"otel_traces"},"kind":"trace","timestampValueExpression":"Timestamp","name":"Traces","displayedTimestampValueExpression":"Timestamp","implicitColumnExpression":"SpanName","serviceNameExpression":"ServiceName","bodyExpression":"SpanName","eventAttributesExpression":"SpanAttributes","resourceAttributesExpression":"ResourceAttributes","defaultTableSelectExpression":"Timestamp,ServiceName,StatusCode,round(Duration/1e6),SpanName","traceIdExpression":"TraceId","spanIdExpression":"SpanId","durationExpression":"Duration","durationPrecision":9,"parentSpanIdExpression":"ParentSpanId","spanNameExpression":"SpanName","spanKindExpression":"SpanKind","statusCodeExpression":"StatusCode","statusMessageExpression":"StatusMessage","connection":"Local ClickHouse","logSourceId":"Logs","metricSourceId":"Metrics"},{"from":{"databaseName":"default","tableName":""},"kind":"metric","timestampValueExpression":"TimeUnix","name":"Metrics","resourceAttributesExpression":"ResourceAttributes","metricTables":{"gauge":"otel_metrics_gauge","histogram":"otel_metrics_histogram","sum":"otel_metrics_sum"},"connection":"Local ClickHouse","logSourceId":"Logs","traceSourceId":"Traces"}]'

            $kubectl -n clickstack create secret generic clickstack-secrets \
              --from-literal="HYPERDX_API_KEY=$HK" \
              --from-literal="OTLP_AUTH_TOKEN=$OTLP_TOKEN" \
              --from-literal="CLICKHOUSE_APP_PASSWORD=$APP_PW" \
              --from-literal="CLICKHOUSE_PASSWORD=$COLL_PW" \
              --from-literal="CLICKHOUSE_USER=otelcollector" \
              --from-literal="EXPRESS_SESSION_SECRET=$SESS" \
              --from-literal="MONGO_PASSWORD=$MONGO_PW" \
              --from-literal="MONGO_URI=mongodb://hyperdx:$MONGO_PW@mongo.clickstack.svc.cluster.local:27017/hyperdx?authSource=admin" \
              --from-literal="DEFAULT_CONNECTIONS=$DEFAULT_CONNECTIONS" \
              --from-literal="DEFAULT_SOURCES=$DEFAULT_SOURCES" \
              --dry-run=client -o yaml | $kubectl apply -f - >/dev/null 2>&1 \
              && echo "Injected clickstack-secrets"

            # ClickHouse users.d — hashed passwords; the server hot-reloads
            # this file when the secret is updated.
            APP_HASH=$(printf '%s' "$APP_PW" | sha256sum | cut -d' ' -f1)
            COLL_HASH=$(printf '%s' "$COLL_PW" | sha256sum | cut -d' ' -f1)
            USERS_XML="<clickhouse><users><app><password_sha256_hex>$APP_HASH</password_sha256_hex><networks><ip>::/0</ip></networks><profile>default</profile><quota>default</quota><grants><query>GRANT SHOW ON *.*, SELECT ON system.*, SELECT ON default.*</query></grants></app><otelcollector><password_sha256_hex>$COLL_HASH</password_sha256_hex><networks><ip>::/0</ip></networks><profile>default</profile><quota>default</quota><grants><query>GRANT SELECT,INSERT,CREATE,SHOW ON default.*</query></grants></otelcollector></users></clickhouse>"
            # Entrypoint-equivalent lockdown: default user is local-only.
            # Required because CLICKHOUSE_SKIP_USER_SETUP=1 (users.d is a
            # read-only secret mount; the entrypoint would fail writing it).
            DEFAULT_USER_XML="<clickhouse><users><default><networks><ip>::1</ip><ip>127.0.0.1</ip></networks></default></users></clickhouse>"
            $kubectl -n clickstack create secret generic clickstack-clickhouse-users \
              --from-literal="users.xml=$USERS_XML" \
              --from-literal="default-user.xml=$DEFAULT_USER_XML" \
              --dry-run=client -o yaml | $kubectl apply -f - >/dev/null 2>&1 \
              && echo "Injected clickstack-clickhouse-users"
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
            for target_ns in cnpg-system edukurs forgejo orkestr mosaic n8n; do
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

          
          # Minecraft RCON password
          if [ -f /run/secrets/minecraft-rcon-password ]; then
            MC_RCON=$(cat /run/secrets/minecraft-rcon-password)
            $kubectl create secret generic minecraft-rcon-secret \
              --namespace=minecraft \
              --from-literal=rcon-password="$MC_RCON" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected minecraft-rcon-secret"
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
            ORKESTR_DNS_CQ="$(cat /run/secrets/orkestr-dns-cluster-query 2>/dev/null || true)"
            if [ -f /run/secrets/orkestr-resend-api-key ]; then
              ORKESTR_RESEND_API_KEY=$(cat /run/secrets/orkestr-resend-api-key)
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
                --from-literal=RESEND_API_KEY="$ORKESTR_RESEND_API_KEY" \
                --from-literal=OPENROUTER_API_KEY="$(cat /run/secrets/orkestr-openrouter-api-key 2>/dev/null || true)" \
                --from-literal=LLM_MODEL="openrouter:deepseek/deepseek-v4-flash" \
                ''${ORKESTR_DNS_CQ:+--from-literal=DNS_CLUSTER_QUERY="$ORKESTR_DNS_CQ"} \
                --dry-run=client -o yaml | $kubectl apply -f -
              echo "Injected orkestr-app-secrets (with RESEND_API_KEY)"
            else
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
                --from-literal=OPENROUTER_API_KEY="$(cat /run/secrets/orkestr-openrouter-api-key 2>/dev/null || true)" \
                --from-literal=LLM_MODEL="openrouter:deepseek/deepseek-v4-flash" \
                ''${ORKESTR_DNS_CQ:+--from-literal=DNS_CLUSTER_QUERY="$ORKESTR_DNS_CQ"} \
                --dry-run=client -o yaml | $kubectl apply -f -
              echo "Injected orkestr-app-secrets"
            fi

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

          # Harbor pull secret for mosaic
          if [ -f /run/secrets/harbor-registry-password ]; then
            HARBOR_REG_PW=$(cat /run/secrets/harbor-registry-password)
            $kubectl create secret docker-registry harbor-registry \
              --namespace=mosaic \
              --docker-server=10.0.0.56:5000 \
              --docker-username=harbor_registry_user \
              --docker-password="$HARBOR_REG_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected harbor-registry (mosaic namespace)"
          fi

          # Mosaic Ceph RGW user → mosaic-s3 (app buckets, not CNPG backups)
          if $kubectl -n rook-ceph get secret rook-ceph-object-user-ceph-objectstore-mosaic >/dev/null 2>&1; then
            MOSAIC_S3_KEY=$($kubectl -n rook-ceph get secret rook-ceph-object-user-ceph-objectstore-mosaic -o jsonpath='{.data.AccessKey}' | base64 -d)
            MOSAIC_S3_SECRET=$($kubectl -n rook-ceph get secret rook-ceph-object-user-ceph-objectstore-mosaic -o jsonpath='{.data.SecretKey}' | base64 -d)
            $kubectl create secret generic mosaic-s3 \
              --namespace=mosaic \
              --from-literal=S3_ENDPOINT="http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc.cluster.local" \
              --from-literal=S3_REGION="us-east-1" \
              --from-literal=S3_FORCE_PATH_STYLE="true" \
              --from-literal=S3_ACCESS_KEY_ID="$MOSAIC_S3_KEY" \
              --from-literal=S3_SECRET_ACCESS_KEY="$MOSAIC_S3_SECRET" \
              --from-literal=S3_BUCKET_ASSETS="catalog-assets" \
              --from-literal=S3_BUCKET_IMPORTS="catalog-imports" \
              --from-literal=S3_BUCKET_RENDERS="catalog-renders" \
              --from-literal=S3_BUCKET_PROMO="catalog-promo" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected mosaic-s3"
          fi

          if [ -f /run/secrets/mosaic-db-password ]; then
            MOSAIC_DB_PW=$(cat /run/secrets/mosaic-db-password)
            $kubectl create secret generic mosaic-db-secret \
              --namespace=mosaic \
              --from-literal=username=mosaic \
              --from-literal=password="$MOSAIC_DB_PW" \
              --from-literal=dbname=mosaic \
              --from-literal=uri="postgresql://mosaic:$MOSAIC_DB_PW@mosaic-db-rw.mosaic.svc.cluster.local:5432/mosaic?sslmode=disable" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected mosaic-db-secret"
          fi

          # n8n
          if [ -f /run/secrets/n8n-db-password ] && [ -f /run/secrets/n8n-encryption-key ]; then
            N8N_DB_PW=$(cat /run/secrets/n8n-db-password)
            N8N_ENC=$(cat /run/secrets/n8n-encryption-key)
            $kubectl create secret generic n8n-db-secret \
              --namespace=n8n \
              --from-literal=username=n8n \
              --from-literal=password="$N8N_DB_PW" \
              --from-literal=dbname=n8n \
              --from-literal=uri="postgresql://n8n:$N8N_DB_PW@n8n-db-rw.n8n.svc.cluster.local:5432/n8n?sslmode=disable" \
              --dry-run=client -o yaml | $kubectl apply -f -
            $kubectl create secret generic n8n-app-secrets \
              --namespace=n8n \
              --from-literal=N8N_ENCRYPTION_KEY="$N8N_ENC" \
              --from-literal=DB_POSTGRESDB_PASSWORD="$N8N_DB_PW" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected n8n-db-secret and n8n-app-secrets"
          fi

          # Kaneo
          if [ -f /run/secrets/kaneo-db-password ] && [ -f /run/secrets/kaneo-auth-secret ]; then
            KANEO_DB_PW=$(cat /run/secrets/kaneo-db-password)
            KANEO_AUTH=$(cat /run/secrets/kaneo-auth-secret)
            $kubectl create secret generic kaneo-db-secret \
              --namespace=kaneo \
              --from-literal=username=kaneo \
              --from-literal=password="$KANEO_DB_PW" \
              --from-literal=dbname=kaneo \
              --dry-run=client -o yaml | $kubectl apply -f -
            $kubectl create secret generic kaneo-app-secrets \
              --namespace=kaneo \
              --from-literal=DATABASE_URL="postgresql://kaneo:$KANEO_DB_PW@kaneo-db-rw.kaneo.svc.cluster.local:5432/kaneo?sslmode=disable" \
              --from-literal=AUTH_SECRET="$KANEO_AUTH" \
              --dry-run=client -o yaml | $kubectl apply -f -
            echo "Injected kaneo-db-secret and kaneo-app-secrets"
          fi

          echo "K8s secrets injection complete."
        '';
      })
      pkgs.kubectl
    ];

    systemd.services.k8s-secrets-inject = {
      description = "Inject SOPS secrets into Kubernetes";
      after = ["network-online.target" "kube-apiserver.service"];
      wants = ["network-online.target" "kube-apiserver.service"];
      wantedBy = ["multi-user.target"];
      environment.KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/sw/bin/k8s-secrets-inject";
      };
    };
  };
}
