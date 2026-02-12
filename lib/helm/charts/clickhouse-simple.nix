{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://charts.bitnami.com/bitnami";
    chart = "clickhouse";
    version = "9.4.4";
    chartHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  clickhouseOperatorChart = helmLib.kubelib.downloadHelmChart {
    repo = "https://charts.bitnami.com/bitnami";
    chart = "clickhouse-operator";
    version = "0.23.0";
    chartHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
  };
in
{
  # ClickHouse - Single Instance Configuration for Cloudflare Tunnel
  clickhouse = helmLib.buildChart {
    name = "clickhouse";
    inherit chart;
    namespace = "clickhouse";
    values = {
      # Single instance cluster (no sharding/replication)
      cluster = {
        name = "clickhouse-cluster";
        shardsCount = 1;
        replicasCount = 1;
      };

      # Image configuration
      image = {
        repository = "clickhouse/clickhouse-server";
        tag = "23.8";
        pullPolicy = "IfNotPresent";
      };

      # Persistence
      persistence = {
        enabled = true;
        size = "100Gi";
        storageClass = "local-path";
      };

      # Service configuration - ClusterIP only (Cloudflare Tunnel handles external access)
      service = {
        type = "ClusterIP";
        httpPort = 8123;
        tcpPort = 9000;
        interserverPort = 9009;
      };

      # Ingress disabled - using Cloudflare Tunnel
      ingress = {
        enabled = false;
      };

      # ClickHouse configuration
      clickhouseConfig = {
        # Logging
        logger = {
          level = "information";
          log = "/var/log/clickhouse-server/clickhouse-server.log";
          errorlog = "/var/log/clickhouse-server/clickhouse-server.err.log";
        };

        # Listen on all interfaces
        listen_host = "::";

        # HTTP interface
        http_port = 8123;
        tcp_port = 9000;
        interserver_http_port = 9009;

        # Users and profiles
        users = {
          default = {
            password = "";
            networks = {
              ip = [ "::/0" ];
            };
            profile = "default";
            quota = "default";
          };
          # Admin user (password should be managed via secrets)
          admin = {
            password = "changeme";
            networks = {
              ip = [ "::/0" ];
            };
            profile = "default";
            quota = "default";
            access_management = 1;
          };
        };

        # Profiles
        profiles = {
          default = {
            max_memory_usage = 10000000000;
            use_uncompressed_cache = 0;
            load_balancing = "random";
          };
          readonly = {
            readonly = 1;
          };
        };

        # Quotas
        quotas = {
          default = {
            interval = {
              duration = 3600;
              queries = 0;
              errors = 0;
              result_rows = 0;
              read_rows = 0;
              execution_time = 0;
            };
          };
        };

        # Compression
        compression = {
          case = {
            method = "zstd";
          };
        };
      };

      # ZooKeeper disabled (not needed for single instance)
      zookeeper = {
        enabled = false;
      };

      # Resource limits (reduced for single instance)
      resources = {
        requests = {
          cpu = "500m";
          memory = "2Gi";
        };
        limits = {
          cpu = "2000m";
          memory = "4Gi";
        };
      };

      # Probes
      livenessProbe = {
        httpGet = {
          path = "/ping";
          port = 8123;
        };
        initialDelaySeconds = 30;
        periodSeconds = 10;
        timeoutSeconds = 5;
        failureThreshold = 3;
      };

      readinessProbe = {
        httpGet = {
          path = "/ping";
          port = 8123;
        };
        initialDelaySeconds = 10;
        periodSeconds = 5;
        timeoutSeconds = 3;
        failureThreshold = 3;
      };

      # Security context
      podSecurityContext = {
        fsGroup = 101;
        runAsUser = 101;
        runAsGroup = 101;
      };

      # Monitoring
      serviceMonitor = {
        enabled = true;
        interval = "30s";
        scrapeTimeout = "10s";
      };
    };
  };

  # ClickHouse Operator - Single Instance
  clickhouse-operator = helmLib.buildChart {
    name = "clickhouse-operator";
    inherit clickhouseOperatorChart;
    namespace = "clickhouse-operator";
    values = {
      # Operator configuration
      operator = {
        # Single operator replica
        replicaCount = 1;

        # Image
        image = {
          repository = "altinity/clickhouse-operator";
          tag = "0.23.0";
          pullPolicy = "IfNotPresent";
        };

        # Resource limits
        resources = {
          requests = {
            cpu = "100m";
            memory = "128Mi";
          };
          limits = {
            cpu = "500m";
            memory = "512Mi";
          };
        };

        # Metrics exporter
        metrics = {
          enabled = true;
          port = 8888;
        };
      };

      # RBAC
      rbac = {
        create = true;
      };

      # Service account
      serviceAccount = {
        create = true;
        name = "clickhouse-operator";
      };

      # Webhook
      webhook = {
        enabled = true;
        port = 9443;
      };
    };
  };
}
