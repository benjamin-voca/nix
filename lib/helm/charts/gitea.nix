{ helmLib }:

{
  # Gitea configuration
  gitea = helmLib.buildChart {
    name = "gitea";
    chart = helmLib.kubelib.downloadHelmChart {
      repo = "https://dl.gitea.com/charts";
      chart = "gitea";
      version = "12.4.0";
      chartHash = "sha256-jIjCFb+v3/uzkxqC84mY48+X5ZrSeHTBssoB8XvsvHg=";
    };
    namespace = "gitea";
    values = {
      # Gitea image configuration
      image = {
        registry = "";
        repository = "gitea/gitea";
        tag = "1.25.4";
        fullOverride = "";
        rootless = false;
        pullPolicy = "IfNotPresent";
      };

      # Replicas for high availability
      replicaCount = 1;

      # Service configuration
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

      # Ingress configuration
      ingress = {
        enabled = true;
        className = "nginx";
        annotations = {
          "nginx.ingress.kubernetes.io/proxy-body-size" = "512m";
        };
        hosts = [{
          host = "gitea.quadtech.dev";
          paths = [{
            path = "/";
            pathType = "Prefix";
          }];
        }];
        tls = [ ];
      };

      # Persistence
      persistence = {
        enabled = true;
        create = true;
        mount = true;
        size = "50Gi";
        storageClass = "longhorn";
        claimName = "gitea-shared-storage";
      };

      # PostgreSQL database
      postgresql = {
        enabled = false;
      };

      postgresql-ha = {
        enabled = false;
      };

      # Redis for caching
      redis-cluster = {
        enabled = false;
      };

      valkey-cluster = {
        enabled = false;
      };

      # Gitea configuration
      gitea = {
        admin = {
          # Admin credentials should be managed via secrets
          existingSecret = "gitea-admin";
          username = "gitea_admin";
          password = "REPLACE_ME";
          email = "admin@quadtech.dev";
        };

        config = {
          log = {
            MODE = "console";
            ROOT_PATH = "/data/gitea/custom/log";
          };
            server = {
            DOMAIN = "gitea.quadtech.dev";
            ROOT_URL = "https://gitea.quadtech.dev";
            SSH_DOMAIN = "gitea.quadtech.dev";
            SSH_PORT = 2222;
            DISABLE_SSH = false;
            START_SSH_SERVER = true;
            SSH_LISTEN_PORT = 22;
          };
          ssh = {
            create = false;
          };

          database = {
            DB_TYPE = "postgres";
            HOST = "gitea-db-rw.gitea.svc.cluster.local:5432";
            NAME = "gitea";
            USER = "gitea";
            PASSWD = "REPLACE_ME";
            SSL_MODE = "disable";
          };

          cache = {
            ENABLED = true;
            ADAPTER = "memory";
          };

          session = {
            PROVIDER = "memory";
          };

          queue = {
            TYPE = "level";
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

        additionalConfigFromEnvs = [
          {
            name = "GITEA__DATABASE__PASSWD";
            valueFrom = {
              secretKeyRef = {
                name = "gitea-db";
                key = "password";
              };
            };
          }
        ];
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

      # Disable broken init containers - let Gitea handle initialization
      initContainers = {
        initDirectories = {
          enabled = false;
        };
        initAppIni = {
          enabled = false;
        };
        configureGitea = {
          enabled = false;
        };
      };

      # Node affinity for HA
      affinity = { };
    };
  };
}
