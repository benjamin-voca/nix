{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://dl.gitea.com/charts";
    chart = "gitea";
    version = "12.5.0";
    chartHash = "sha256-6sG9xCpbbRMMDlsZtHzqrNWuqsT/NHalUVUv0Ltx/zA=";
  };
in
{
  # Gitea - Single Instance Configuration for Cloudflare Tunnel
  gitea = helmLib.buildChart {
    name = "gitea";
    inherit chart;
    namespace = "gitea";
    values = {
      # Gitea image configuration
      image = {
        repository = "gitea/gitea";
        tag = "1.21.3";
        pullPolicy = "IfNotPresent";
      };

      # Single replica (no HA)
      replicaCount = 1;

      # Service configuration - ClusterIP only (Cloudflare Tunnel handles external access)
      service = {
        http = {
          type = "ClusterIP";
          port = 3000;
        };
        ssh = {
          type = "ClusterIP";
          port = 22;
        };
      };

      # Ingress disabled - using Cloudflare Tunnel
      ingress = {
        enabled = false;
      };

      # Persistence
      persistence = {
        enabled = true;
        size = "50Gi";
        storageClass = "local-path";
      };

      # PostgreSQL database
      postgresql = {
        enabled = true;
        global = {
          postgresql = {
            auth = {
              database = "gitea";
              username = "gitea";
              # Password should be managed via secrets
              password = "changeme";
            };
          };
        };
        primary = {
          persistence = {
            enabled = true;
            size = "20Gi";
          };
        };
      };

      # Redis for caching
      redis-cluster = {
        enabled = true;
        usePassword = false;
      };

      # Gitea configuration
      gitea = {
        admin = {
          # Admin credentials should be managed via secrets
          username = "gitea_admin";
          password = "changeme";
          email = "admin@quadtech.dev";
        };

        config = {
          server = {
            DOMAIN = "gitea.quadtech.dev";
            ROOT_URL = "https://gitea.quadtech.dev";
            SSH_DOMAIN = "gitea.quadtech.dev";
            SSH_PORT = 22;
            DISABLE_SSH = false;
            START_SSH_SERVER = true;
            SSH_LISTEN_PORT = 22;
          };

          database = {
            DB_TYPE = "postgres";
            HOST = "gitea-postgresql:5432";
            NAME = "gitea";
            USER = "gitea";
            # Password from secret
          };

          cache = {
            ENABLED = true;
            ADAPTER = "redis";
            HOST = "redis://gitea-redis-cluster:6379/0";
          };

          session = {
            PROVIDER = "redis";
            PROVIDER_CONFIG = "redis://gitea-redis-cluster:6379/1";
          };

          queue = {
            TYPE = "redis";
            CONN_STR = "redis://gitea-redis-cluster:6379/2";
          };

          service = {
            DISABLE_REGISTRATION = false;
            REQUIRE_SIGNIN_VIEW = false;
            ENABLE_NOTIFY_MAIL = false;
          };

          actions = {
            ENABLED = true;
          };

          repository = {
            DEFAULT_BRANCH = "main";
            ENABLE_PUSH_CREATE_USER = true;
            ENABLE_PUSH_CREATE_ORG = true;
          };

          webhook = {
            ALLOWED_HOST_LIST = "*";
          };
        };
      };

      # Resource limits (reduced for single instance)
      resources = {
        requests = {
          cpu = "200m";
          memory = "512Mi";
        };
        limits = {
          cpu = "1000m";
          memory = "2Gi";
        };
      };

      # Probes
      livenessProbe = {
        enabled = true;
        initialDelaySeconds = 30;
        periodSeconds = 10;
        timeoutSeconds = 5;
      };

      readinessProbe = {
        enabled = true;
        initialDelaySeconds = 10;
        periodSeconds = 5;
        timeoutSeconds = 3;
      };

      # Security context
      podSecurityContext = {
        fsGroup = 1000;
      };
    };
  };
}
