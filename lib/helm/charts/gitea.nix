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
           type = "NodePort";
           port = 22;
           targetPort = 2223;
           clusterIP = "";
           annotations = {
             "external-dns.alpha.kubernetes.io/hostname" = "gitea-ssh.quadtech.dev";
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
        storageClass = "ceph-block";
        claimName = "gitea-shared-storage-ceph";
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
            SSH_DOMAIN = "gitea-ssh.quadtech.dev";
            SSH_PORT = 22;
            DISABLE_SSH = false;
            START_SSH_SERVER = true;
            SSH_LISTEN_PORT = 22;
            SSH_SERVER_HOST_KEYS = "gitea/ssh/gitea.rsa,gitea/ssh/gitea.ed25519";
          };
          ssh = {
            create = true;
          };

          database = {
            DB_TYPE = "postgres";
            HOST = "gitea-db-ceph-rw.gitea.svc.cluster.local:5432";
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

      # Generate SSH host keys on first startup and persist them
      preExtraInitContainers = [
        {
          name = "ssh-host-keys";
          image = "gitea/gitea:1.25.4";
          command = [ "sh" "-c" ];
          args = [''
            echo "Checking for SSH host keys in /data/gitea/ssh..."
            mkdir -p /data/gitea/ssh
            mkdir -p /etc/ssh
            if [ ! -f /data/gitea/ssh/gitea.rsa ]; then
              echo "Generating new SSH host keys..."
              ssh-keygen -t rsa -b 4096 -f /data/gitea/ssh/gitea.rsa -N "" -C "gitea@quadtech.dev"
              ssh-keygen -t ed25519 -f /data/gitea/ssh/gitea.ed25519 -N "" -C "gitea@quadtech.dev"
              echo "SSH host keys generated"
            else
              echo "Using existing SSH host keys from persistent storage"
            fi
            echo "Copying SSH host keys to /etc/ssh..."
            cp /data/gitea/ssh/gitea.rsa /etc/ssh/ssh_host_rsa_key
            cp /data/gitea/ssh/gitea.rsa.pub /etc/ssh/ssh_host_rsa_key.pub
            cp /data/gitea/ssh/gitea.ed25519 /etc/ssh/ssh_host_ed25519_key
            cp /data/gitea/ssh/gitea.ed25519.pub /etc/ssh/ssh_host_ed25519_key.pub
            chmod 600 /etc/ssh/ssh_host_*
            chmod 644 /etc/ssh/ssh_host_*.pub
            ls -la /etc/ssh/
            ls -la /data/gitea/ssh/
            echo "Done"
          ''];
          volumeMounts = [
            {
              name = "data";
              mountPath = "/data";
            }
          ];
          resources = {
            requests = { cpu = "10m"; memory = "16Mi"; };
            limits = { cpu = "100m"; memory = "64Mi"; };
          };
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
          };
        }
      ];

      # Use postExtraInitContainers which is supported by the Gitea chart
      # Wait for app.ini to be created and copy to /etc/gitea for SSH hooks
      postExtraInitContainers = [
        {
          name = "fix-app-ini-permissions";
          image = "gitea/gitea:1.25.4";
          command = [ "sh" "-c" ];
          args = [''
            echo "Waiting for Gitea to generate app.ini..."
            while [ ! -f /data/gitea/conf/app.ini ]; do sleep 2; done
            sleep 2
            mkdir -p /etc/gitea
            cp /data/gitea/conf/app.ini /etc/gitea/app.ini
            chown -R 1000:1000 /etc/gitea
            echo "Copied app.ini to /etc/gitea"
          ''];
          volumeMounts = [
            {
              name = "data";
              mountPath = "/data";
            }
          ];
          resources = {
            requests = { cpu = "10m"; memory = "16Mi"; };
            limits = { cpu = "100m"; memory = "64Mi"; };
          };
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
          };
        }
        {
          name = "fix-permissions";
          image = "gitea/gitea:1.25.4";
          command = [ "sh" "-c" ];
          args = [''
            echo "Fixing volume permissions..."
            chown -R 1000:1000 /data
            chmod -R 755 /data
            # Fix SSH keys specifically - they must be readable by git user
            if [ -d /data/gitea/ssh ]; then
              chown -R 1000:1000 /data/gitea/ssh
              chmod 600 /data/gitea/ssh/*
              chmod 644 /data/gitea/ssh/*.pub 2>/dev/null || true
            fi
            # Fix git user ssh directory
            if [ -d /data/git ]; then
              chown -R 1000:1000 /data/git
              if [ -d /data/git/.ssh ]; then
                chmod 700 /data/git/.ssh
                chmod 600 /data/git/.ssh/*
              fi
            fi
            # Create symlink for Gitea hooks that expect /etc/gitea
            mkdir -p /etc/gitea
            cp /data/gitea/conf/app.ini /etc/gitea/app.ini
            chown -R 1000:1000 /etc/gitea
            ls -la /data/gitea/ssh/ 2>/dev/null || true
            echo "Done"
          ''];
          volumeMounts = [
            {
              name = "data";
              mountPath = "/data";
            }
          ];
          resources = {
            requests = { cpu = "10m"; memory = "16Mi"; };
            limits = { cpu = "100m"; memory = "64Mi"; };
          };
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
          };
        }
      ];

      # Note: Run as root - Gitea container uses s6-overlay which requires root
      # Gitea process drops to UID 1000 internally

      # Node affinity for HA
      affinity = { };
    };
  };
}
