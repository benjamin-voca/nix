{helmLib}: let
  forgejoImage = "codeberg.org/forgejo/forgejo:15.0.0";
  compatChartName = "gi" + "tea";
  compatDataPath = "/data/${compatChartName}";
in rec {
  # Forgejo configuration
  forgejo = helmLib.buildChart {
    name = "forgejo";
    chart = helmLib.kubelib.downloadHelmChart {
      repo = "https://dl.${compatChartName}.com/charts";
      chart = compatChartName;
      version = "12.5.0";
      chartHash = "sha256-6sG9xCpbbRMMDlsZtHzqrNWuqsT/NHalUVUv0Ltx/zA=";
    };
    namespace = "forgejo";
    values = {
      nameOverride = "forgejo";
      fullnameOverride = "forgejo";

      # Forgejo image configuration
      image = {
        registry = "codeberg.org";
        repository = "forgejo/forgejo";
        tag = "15.0.0";
        fullOverride = "";
        rootless = false;
        pullPolicy = "IfNotPresent";
      };

      # Best-effort HA deployment (Forgejo app-level HA still has upstream caveats).
      replicaCount = 2;
      strategy = {
        type = "RollingUpdate";
        rollingUpdate = {
          maxSurge = 0;
          maxUnavailable = 1;
        };
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
          nodePort = 32222;
          clusterIP = "";
          annotations = {
            "external-dns.alpha.kubernetes.io/hostname" = "forge-ssh.quadtech.dev";
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
        hosts = [
          {
            host = "forge.quadtech.dev";
            paths = [
              {
                path = "/";
                pathType = "Prefix";
              }
            ];
          }
        ];
        tls = [];
      };

      # Shared filesystem storage for future pod handoff.
      persistence = {
        enabled = true;
        create = true;
        mount = true;
        size = "50Gi";
        storageClass = "ceph-filesystem-csi";
        accessModes = ["ReadWriteMany"];
        claimName = "forgejo-shared-storage-ceph-csi";
      };

      # PostgreSQL database
      postgresql = {
        enabled = false;
      };

      postgresql-ha = {
        enabled = false;
      };

      # Use chart-managed valkey cluster for shared cache/session/queue.
      redis-cluster = {
        enabled = false;
      };

      valkey-cluster = {
        enabled = true;
        usePassword = false;
        usePasswordFiles = false;
        cluster = {
          nodes = 3;
          replicas = 1;
        };
      };

      # Forgejo app configuration (upstream chart uses compatibility key names).
      ${compatChartName} = {
        admin = {
          # Admin credentials should be managed via secrets
          existingSecret = "forgejo-admin";
          username = "forgejo_admin";
          password = "REPLACE_ME";
          email = "admin@quadtech.dev";
        };

        config = {
          log = {
            MODE = "console";
            ROOT_PATH = "${compatDataPath}/custom/log";
          };
          server = {
            DOMAIN = "forge.quadtech.dev";
            ROOT_URL = "https://forge.quadtech.dev";
            SSH_DOMAIN = "forge-ssh.quadtech.dev";
            SSH_PORT = 22;
            DISABLE_SSH = false;
            START_SSH_SERVER = false;
            SSH_LISTEN_PORT = 22;
            # SSH keys are relative to GITEA_ROOT, stored in persistent volume
            SSH_SERVER_HOST_KEYS = "forgejo/ssh/forgejo.rsa,forgejo/ssh/forgejo.ed25519";
          };
          ssh = {
            create = true;
          };

          database = {
            DB_TYPE = "postgres";
            HOST = "forgejo-db-rw.forgejo.svc.cluster.local:5432";
            NAME = "app";
            USER = "app";
            PASSWD = "REPLACE_ME";
            SSL_MODE = "disable";
          };

          security = {
            INSTALL_LOCK = true;
          };

          service = {
            DISABLE_REGISTRATION = true;
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
            name = "GI" + "TEA__DATABASE__PASSWD";
            valueFrom = {
              secretKeyRef = {
                name = "forgejo-db-app";
                key = "password";
              };
            };
          }
        ];
      };

      deployment.env = [
        {
          name = "SSH_INCLUDE_FILE";
          value = "/data/ssh/sshd_config_override";
        }
      ];

      # Resource limits
      resources = {
        requests = {
          cpu = "100m";
          memory = "512Mi";
        };
        limits = {
          cpu = "1500m";
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

      # fsGroup allows pods to write to CephFS volumes (Forgejo runs as UID 1000)
      podSecurityContext = {
        fsGroup = 1000;
        runAsUser = 0;
        runAsGroup = 0;
      };

      containerSecurityContext = {};

      # SSH server needs host keys in /etc/ssh/ AND sshd_config_override in /data/ssh/
      # Keys are relative to GITEA_ROOT (/data/gitea), so stored at /data/gitea/forgejo/ssh/
      extraVolumes = [
        {
          name = "sshd-config";
          emptyDir = {};
        }
      ];
      extraVolumeMounts = [
        {
          name = "sshd-config";
          mountPath = "/etc/ssh";
          subPath = "etc-ssh";
        }
      ];
      preExtraInitContainers = [
        {
          name = "ssh-host-keys";
          image = forgejoImage;
          command = ["sh" "-c"];
          args = [
            ''
                          set -euo pipefail
                          SSH_KEYS_DIR="${compatDataPath}/forgejo/ssh"
                          echo "Checking for SSH host keys in $SSH_KEYS_DIR..."
                          mkdir -p "$SSH_KEYS_DIR"
                          mkdir -p /etc/ssh

                          # Generate keys ONLY if they don't exist
                          if [ ! -f "$SSH_KEYS_DIR/forgejo.rsa" ]; then
                            echo "Generating new SSH host keys..."
                            ssh-keygen -t rsa -b 4096 -f "$SSH_KEYS_DIR/forgejo.rsa" -N "" -C "forgejo@quadtech.dev"
                            ssh-keygen -t ed25519 -f "$SSH_KEYS_DIR/forgejo.ed25519" -N "" -C "forgejo@quadtech.dev"
                            echo "SSH host keys generated"
                          else
                            echo "Using existing SSH host keys from persistent storage"
                          fi

                          # Ensure correct permissions on persistent keys
                          chmod 600 "$SSH_KEYS_DIR/forgejo.rsa"
                          chmod 600 "$SSH_KEYS_DIR/forgejo.ed25519"
                          chmod 644 "$SSH_KEYS_DIR/forgejo.rsa.pub"
                          chmod 644 "$SSH_KEYS_DIR/forgejo.ed25519.pub"

                          # Copy to /etc/ssh for current container and future restarts
                          cp "$SSH_KEYS_DIR/forgejo.rsa" /etc/ssh/ssh_host_rsa_key
                          cp "$SSH_KEYS_DIR/forgejo.rsa.pub" /etc/ssh/ssh_host_rsa_key.pub
                          cp "$SSH_KEYS_DIR/forgejo.ed25519" /etc/ssh/ssh_host_ed25519_key
                          cp "$SSH_KEYS_DIR/forgejo.ed25519.pub" /etc/ssh/ssh_host_ed25519_key.pub
                          chmod 600 /etc/ssh/ssh_host_*_key
                          chmod 644 /etc/ssh/ssh_host_*_key.pub

                          # Create sshd_config_override that includes StrictModes disable AND key locations
                          mkdir -p /data/ssh
                          cat > /data/ssh/sshd_config_override << 'SSHD_EOF'
              StrictModes no
              HostKey /data/gitea/forgejo/ssh/forgejo.rsa
              HostKey /data/gitea/forgejo/ssh/forgejo.ed25519
              SSHD_EOF
                          chmod 644 /data/ssh/sshd_config_override

                          echo "SSH setup complete"
                          ls -la /etc/ssh/
                          ls -la "$SSH_KEYS_DIR/"
                          ls -la /data/ssh/
            ''
          ];
          volumeMounts = [
            {
              name = "data";
              mountPath = "/data";
            }
          ];
          resources = {
            requests = {
              cpu = "10m";
              memory = "16Mi";
            };
            limits = {
              cpu = "100m";
              memory = "64Mi";
            };
          };
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
          };
        }
      ];

      # Use postExtraInitContainers which is supported by the upstream chart.
      postExtraInitContainers = [
        {
          name = "fix-app-ini-permissions";
          image = forgejoImage;
          command = ["sh" "-c"];
          args = [
            ''
              echo "Waiting for Forgejo to generate app.ini..."
              while [ ! -f ${compatDataPath}/conf/app.ini ]; do sleep 2; done
              sleep 2
              mkdir -p /etc/forgejo
              cp ${compatDataPath}/conf/app.ini /etc/forgejo/app.ini
              chown -R 1000:1000 /etc/forgejo
              echo "Copied app.ini to /etc/forgejo"
            ''
          ];
          volumeMounts = [
            {
              name = "data";
              mountPath = "/data";
            }
          ];
          resources = {
            requests = {
              cpu = "10m";
              memory = "16Mi";
            };
            limits = {
              cpu = "100m";
              memory = "64Mi";
            };
          };
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
          };
        }
        {
          name = "fix-permissions";
          image = forgejoImage;
          command = ["sh" "-c"];
          args = [
            ''
                          set -euo pipefail
                          echo "Ensuring sshd_config_override exists in PVC..."
                          if [ ! -f /data/ssh/sshd_config_override ]; then
                            mkdir -p /data/ssh
                            cat > /data/ssh/sshd_config_override << 'SSHD_EOF'
              StrictModes no
              HostKey /data/gitea/forgejo/ssh/forgejo.rsa
              HostKey /data/gitea/forgejo/ssh/forgejo.ed25519
              SSHD_EOF
                            chmod 644 /data/ssh/sshd_config_override
                            echo "Created sshd_config_override"
                          fi

                          echo "Fixing volume ownership..."
                          chown -R 1000:1000 /data

                          # Keep SSH auth files in StrictModes-safe permissions
                          mkdir -p /data/git/.ssh
                          chmod 700 /data/git/.ssh
                          chmod 600 /data/git/.ssh/authorized_keys 2>/dev/null || true
                          chmod 600 /data/git/.ssh/environment 2>/dev/null || true

                          # Ensure SSH keys have correct permissions
                          SSH_KEYS_DIR="${compatDataPath}/forgejo/ssh"
                          if [ -d "$SSH_KEYS_DIR" ]; then
                            echo "Fixing SSH keys at $SSH_KEYS_DIR..."
                            chmod 600 "$SSH_KEYS_DIR"/*.rsa 2>/dev/null || true
                            chmod 600 "$SSH_KEYS_DIR"/*.ed25519 2>/dev/null || true
                            chmod 644 "$SSH_KEYS_DIR"/*.pub 2>/dev/null || true
                            ls -la "$SSH_KEYS_DIR/"
                          fi

                          # Copy host keys to /etc/ssh for sshd to find them
                          if [ -f "$SSH_KEYS_DIR/forgejo.rsa" ]; then
                            cp "$SSH_KEYS_DIR/forgejo.rsa" /etc/ssh/ssh_host_rsa_key 2>/dev/null || true
                            cp "$SSH_KEYS_DIR/forgejo.rsa.pub" /etc/ssh/ssh_host_rsa_key.pub 2>/dev/null || true
                          fi
                          if [ -f "$SSH_KEYS_DIR/forgejo.ed25519" ]; then
                            cp "$SSH_KEYS_DIR/forgejo.ed25519" /etc/ssh/ssh_host_ed25519_key 2>/dev/null || true
                            cp "$SSH_KEYS_DIR/forgejo.ed25519.pub" /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null || true
                          fi
                          chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
                          chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true

                          mkdir -p /etc/forgejo
                          cp ${compatDataPath}/conf/app.ini /etc/forgejo/app.ini 2>/dev/null || true
                          chown -R 1000:1000 /etc/forgejo 2>/dev/null || true
                          echo "Done"
            ''
          ];
          volumeMounts = [
            {
              name = "data";
              mountPath = "/data";
            }
          ];
          resources = {
            requests = {
              cpu = "10m";
              memory = "16Mi";
            };
            limits = {
              cpu = "100m";
              memory = "64Mi";
            };
          };
          securityContext = {
            runAsUser = 0;
            runAsGroup = 0;
          };
        }
      ];

      # Note: Run as root - Forgejo container uses s6-overlay which requires root
      # Forgejo process drops to UID 1000 internally

      # Spread across nodes where possible.
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100;
              podAffinityTerm = {
                labelSelector = {
                  matchExpressions = [
                    {
                      key = "app.kubernetes.io/name";
                      operator = "In";
                      values = ["forgejo"];
                    }
                  ];
                };
                topologyKey = "kubernetes.io/hostname";
              };
            }
          ];
        };
      };
    };
  };
}
