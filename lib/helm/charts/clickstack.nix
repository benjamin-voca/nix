# ClickStack (HyperDX) — minimal mode
#
# Only the HyperDX app is rendered from the upstream chart. ClickHouse,
# MongoDB and the OTel collector are self-managed declaratively in
# modules/outputs/bootstrap/clickstack.nix (no operators, no CRDs — the
# cluster runs a single node and cert-manager is currently down, so the
# operator-based default install is not viable).
#
# HyperDX reads its credentials from the externally managed secret
# `clickstack-secrets` (created by k8s-secrets-inject on the host, values
# from sops: clickstack-* keys). The chart's own secret creation is
# disabled via hyperdx.secrets = null, which upstream requires all three
# bundled subcomponents to be disabled — exactly the mode we use.
#
# All workloads tolerate the backbone taints (role=backbone, infra=true).
{helmLib}: let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://clickhouse.github.io/ClickStack-helm-charts";
    chart = "clickstack";
    version = "3.2.0";
    chartHash = "sha256-EYBhOCoffS0e80x3Gh9QCBP7mC/sQKEv35b/BcDxOK4=";
  };
in {
  clickstack = helmLib.buildChart {
    name = "clickstack";
    inherit chart;
    namespace = "clickstack";
    values = {
      # ── Disable everything except HyperDX ────────────────────────────────
      mongodb.enabled = false;
      "otel-collector".enabled = false;

      # Ports must stay defined: the chart's clickstack-config ConfigMap
      # templates reference clickhouse.*.port even when disabled.
      clickhouse = {
        enabled = false;
        port = 8123;
        nativePort = 9000;
        prometheus = {
          enabled = false;
          port = 9363;
        };
      };

      hyperdx = {
        # Required: no chart-managed secret in external-secrets mode
        secrets = null;

        ports = {
          api = 8000;
          app = 3000;
          opamp = 4320;
        };

        # Non-sensitive shared config (clickstack-config ConfigMap).
        # Sensitive values (MONGO_URI, passwords, API key) are injected per-var
        # from the clickstack-secrets secret via deployment.env overrides.
        config = {
          APP_PORT = "3000";
          API_PORT = "8000";
          HYPERDX_API_PORT = "8000";
          HYPERDX_APP_PORT = "3000";
          HYPERDX_LOG_LEVEL = "info";
          OTEL_SERVICE_NAME = "hdx-oss-api";
          USAGE_STATS_ENABLED = "false";
          OPAMP_PORT = "4320";
          HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE = "default";
          # HyperDX app's own ClickHouse connection (schema/queries)
          CLICKHOUSE_USER = "otelcollector";
          CLICKHOUSE_ENDPOINT = "tcp://clickhouse.clickstack.svc.cluster.local:9000?dial_timeout=10s";
          CLICKHOUSE_SERVER_ENDPOINT = "clickhouse.clickstack.svc.cluster.local:9000";
          CLICKHOUSE_PROMETHEUS_METRICS_ENDPOINT = "http://clickhouse.clickstack.svc.cluster.local:9363";
          # UI / self-instrumentation
          FRONTEND_URL = "https://hyperdx.voltrum.co";
          OTEL_EXPORTER_OTLP_ENDPOINT = "http://clickstack-otel-collector.clickstack.svc.cluster.local:4318";
          # Placeholder: chart default templates dereference hyperdx.secrets
          # (nil here). Real MONGO_URI is injected via deployment.env from the
          # managed secret, which overrides envFrom per-variable.
          MONGO_URI = "mongodb://hyperdx:injected-via-clickstack-secrets@mongo.clickstack.svc.cluster.local:27017/hyperdx?authSource=admin";
          RUN_SCHEDULED_TASKS_EXTERNALLY = "false";
        };

        deployment = {
          image = {
            repository = "docker.hyperdx.io/hyperdx/hyperdx";
            tag = ""; # chart appVersion
            pullPolicy = "IfNotPresent";
          };
          replicas = 1;
          resources = {
            requests = {
              cpu = "150m";
              memory = "512Mi";
            };
            limits = {
              cpu = "1";
              memory = "1536Mi";
            };
          };

          # Connections + sources seed come from the managed secret
          useExistingConfigSecret = true;
          existingConfigSecret = "clickstack-secrets";

          # Sensitive env injected from the managed secret (overrides envFrom)
          env = [
            {
              name = "MONGO_URI";
              valueFrom.secretKeyRef = {
                name = "clickstack-secrets";
                key = "MONGO_URI";
              };
            }
            {
              name = "HYPERDX_API_KEY";
              valueFrom.secretKeyRef = {
                name = "clickstack-secrets";
                key = "HYPERDX_API_KEY";
              };
            }
            {
              name = "CLICKHOUSE_PASSWORD";
              valueFrom.secretKeyRef = {
                name = "clickstack-secrets";
                key = "CLICKHOUSE_PASSWORD";
              };
            }
            {
              name = "CLICKHOUSE_APP_PASSWORD";
              valueFrom.secretKeyRef = {
                name = "clickstack-secrets";
                key = "CLICKHOUSE_APP_PASSWORD";
              };
            }
            {
              name = "EXPRESS_SESSION_SECRET";
              valueFrom.secretKeyRef = {
                name = "clickstack-secrets";
                key = "EXPRESS_SESSION_SECRET";
              };
            }
          ];

          # Wait for Mongo + ClickHouse before starting the app
          initContainers = [
            {
              name = "wait-for-dependencies";
              image = "busybox@sha256:1fcf5df59121b92d61e066df1788e8df0cc35623f5d62d9679a41e163b6a0cdb";
              imagePullPolicy = "IfNotPresent";
              command = ["sh" "-c" "until nc -z mongo.clickstack.svc.cluster.local 27017 && nc -z clickhouse.clickstack.svc.cluster.local 8123; do echo waiting for mongo+clickhouse; sleep 3; done;"];
            }
          ];

          tolerations = [
            {
              key = "role";
              value = "backbone";
              effect = "NoSchedule";
            }
            {
              key = "infra";
              value = "true";
              effect = "NoSchedule";
            }
          ];
        };

        service.apiPort.enabled = false;
        ingress.enabled = false; # own ingress in bootstrap module
        podDisruptionBudget.enabled = false;
        autoscaling.enabled = false;
        networkPolicy.enabled = false;
        serviceAccount.create = false;
        tasks.enabled = false;
      };
    };
  };
}
