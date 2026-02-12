{ helmLib }:

{
  # Gitea configuration
  gitea = helmLib.buildChart {
    name = "gitea";
    chart = helmLib.kubelib.downloadHelmChart {
      repo = "https://dl.gitea.com/charts";
      chart = "gitea";
      version = "12.5.0";
      chartHash = "sha256-6sG9xCpbbRMMDlsZtHzqrNWuqsT/NHalUVUv0Ltx/zA=";
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

      # Replicas - must be 1 since LevelDB queue doesn't support multiple pods
      replicaCount = 1;

      # Strategy: Recreate ensures only one pod accesses storage at a time
      # (LevelDB queue doesn't support concurrent access)
      strategy = {
        type = "Recreate";
      };

      # Service configuration
      service = {
        http = {
          type = "ClusterIP";
          port = 3000;
          clusterIP = "";
        };
         ssh = {
           create = true;
           type = "ClusterIP";
           port = 22;
           targetPort = 22;
           clusterIP = "";
           annotations = {
             "external-dns.alpha.kubernetes.io/hostname" = "gitea-ssh-internal.quadtech.dev";
           };
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
             SSH_PORT = 22;
             DISABLE_SSH = false;
             START_SSH_SERVER = false;
             SSH_LISTEN_PORT = 22;
           };
          ssh = {
            create = true;
          };

          database = {
            DB_TYPE = "postgres";
            HOST = "gitea-db-rw.gitea.svc.cluster.local:5432";
            NAME = "gitea";
            USER = "gitea";
            PASSWD = "REPLACE_ME";
            SSL_MODE = "disable";
          };

          security = {
            INSTALL_LOCK = true;
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
            DISABLE_REGISTRATION = true;
            REQUIRE_SIGNIN_VIEW = true;
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

      # Security context - let rootful image manage its own user (s6-overlay needs root for init)
      podSecurityContext = {
        fsGroup = 1000;
      };

      containerSecurityContext = { };

      # Note: Run as root - Gitea container uses s6-overlay which requires root
      # Gitea process drops to UID 1000 internally

      # Init containers
      postExtraInitContainers = [
        {
          name = "fix-ssh-permissions";
          image = "busybox:latest";
          command = [ "sh" "-c" ];
          args = [''
            echo "Fixing SSH key permissions..."
            if [ -d /data/ssh ]; then
              chown 1000:1000 /data/ssh
              chmod 700 /data/ssh
              for key in /data/ssh/gitea.rsa /data/ssh/ssh_host_*_key; do
                if [ -f "$key" ]; then
                  chmod 600 "$key"
                  chown 1000:1000 "$key"
                  echo "Fixed $key permissions (owned by git user)"
                fi
              done
              for pubkey in /data/ssh/*.pub; do
                if [ -f "$pubkey" ]; then
                  chmod 644 "$pubkey"
                  chown 1000:1000 "$pubkey"
                  echo "Fixed $pubkey permissions"
                fi
              done
              ls -la /data/ssh/
            else
              echo "SSH directory not found"
            fi
          ''];
          volumeMounts = [
            {
              name = "data";
              mountPath = "/data";
            }
          ];
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
          };
        }
      ];

      # Node affinity for HA
      affinity = { };
    };
  };
}
