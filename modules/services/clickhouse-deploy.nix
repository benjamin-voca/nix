{ config, lib, pkgs, ... }:

{
  options.services.quadnix.clickhouse-deploy = {
    enable = lib.mkEnableOption "Deploy ClickHouse with HA configuration";
    
    shards = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Number of ClickHouse shards for HA";
    };
    
    replicasPerShard = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Number of replicas per shard";
    };
    
    zookeeper = {
      enable = lib.mkEnableOption "Deploy ZooKeeper for ClickHouse replication";
      replicas = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Number of ZooKeeper replicas";
      };
    };
    
    storage = {
      size = lib.mkOption {
        type = lib.types.str;
        default = "100Gi";
        description = "Storage size per ClickHouse pod";
      };
    };
  };

  config = lib.mkIf config.services.quadnix.clickhouse-deploy.enable {
    # ClickHouse chart configuration
    environment.etc."clickhouse/values.yaml".text = lib.generators.toYAML {} {
      # ClickHouse cluster configuration
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
        size = config.services.quadnix.clickhouse-deploy.storage.size;
        storageClass = "local-path";
      };

      # Service configuration
      service = {
        type = "ClusterIP";
        httpPort = 8123;
        tcpPort = 9000;
        interserverPort = 9009;
      };

      # Ingress for HTTP interface
      ingress = {
        enabled = true;
        className = "nginx";
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
        };
        hosts = [{
          host = "clickhouse.quadtech.dev";
          paths = [{
            path = "/";
            pathType = "Prefix";
          }];
        }];
        tls = [{
          secretName = "clickhouse-tls";
          hosts = [ "clickhouse.quadtech.dev" ];
        }];
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
            password = "${config.sops.secrets.clickhouse-admin-password.path}";
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

        # Distributed DDL
        distributed_ddl = {
          path = "/clickhouse/task_queue/ddl";
        };
      };

      # ZooKeeper configuration for replication
      zookeeper = {
        enabled = false;
      };

      # Resource limits
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

      # Pod disruption budget for HA
      podDisruptionBudget = {
        enabled = true;
        minAvailable = 1;
      };

      # Security context
      podSecurityContext = {
        fsGroup = 101;
        runAsUser = 101;
        runAsGroup = 101;
      };

      # Anti-affinity for spreading pods across nodes
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [];
        };
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [{
              matchExpressions = [{
                key = "role";
                operator = "In";
                values = [ "backbone" ];
              }];
            }];
          };
        };
      };

      # Monitoring
      serviceMonitor = {
        enabled = true;
        interval = "30s";
        scrapeTimeout = "10s";
      };

      # Tolerations for backbone taints
      tolerations = [
        { key = "role"; operator = "Equal"; value = "backbone"; effect = "NoSchedule"; }
        { key = "infra"; operator = "Equal"; value = "true"; effect = "NoSchedule"; }
      ];
    };

    # ClickHouse Operator configuration
    environment.etc."clickhouse/operator-values.yaml".text = lib.generators.toYAML {} {
      # Operator configuration
      operator = {
        # Number of operator replicas
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

    # ClickHouse ServiceMonitor for Prometheus
    environment.etc."clickhouse/servicemonitor.yaml".text = lib.generators.toYAML {} {
      apiVersion: monitoring.coreos.com/v1
      kind: ServiceMonitor
      metadata:
        name: clickhouse
        namespace: clickhouse
        labels:
          app: clickhouse
      spec:
        selector:
          matchLabels:
            app: clickhouse
        endpoints:
        - port: http
          path: /metrics
          interval: 30s
          scrapeTimeout: 10s
    };
  };
}