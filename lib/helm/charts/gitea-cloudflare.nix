{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://dl.gitea.com/charts";
    chart = "gitea";
    version = "12.5.0";
    chartHash = "sha256-6sG9xCpbbRMMDlsZtHzqrNWuqsT/NHalUVUv0Ltx/zA=";
  };
in
# Gitea configuration optimized for Cloudflare Tunnel
# - No LoadBalancer (uses ClusterIP)
# - No TLS configuration (Cloudflare handles it)
# - Direct routing via Cloudflare Tunnel

{
  # Gitea configuration
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

      # Replicas for high availability
      replicaCount = 2;

      # Service configuration - ClusterIP for Cloudflare Tunnel
      service = {
        http = {
          type = "ClusterIP";  # NOT LoadBalancer - Cloudflare Tunnel handles external access
          port = 3000;
        };
        ssh = {
          type = "ClusterIP";  # SSH via Cloudflare Tunnel or separate tunnel
          port = 22;
          externalPort = 2222;
        };
      };

      # Ingress - Optional, can be disabled since Cloudflare Tunnel handles routing
      ingress = {
        enabled = false;  # Cloudflare Tunnel routes directly to service
        # If you want to use ingress for internal routing:
        # enabled = true;
        # className = "nginx";
        # annotations = {
        #   # NO cert-manager annotation - Cloudflare handles TLS
        # };
        # hosts = [{
        #   host = "gitea.quadtech.dev";
        #   paths = [{
        #     path = "/";
        #     pathType = "Prefix";
        #   }];
        # }];
        # # NO tls section - Cloudflare handles TLS termination
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
            ROOT_URL = "https://gitea.quadtech.dev";  # Cloudflare provides HTTPS
            SSH_DOMAIN = "gitea.quadtech.dev";
            SSH_PORT = 2222;
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

      # Resource limits
      resources = {
        requests = {
          cpu = "200m";
          memory = "512Mi";
        };
        limits = {
          cpu = "2000m";
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

      # Node affinity for HA
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [{
            weight = 100;
            podAffinityTerm = {
              labelSelector = {
                matchExpressions = [{
                  key = "app";
                  operator = "In";
                  values = [ "gitea" ];
                }];
              };
              topologyKey = "kubernetes.io/hostname";
            };
          }];
        };
      };
    };
  };
}
