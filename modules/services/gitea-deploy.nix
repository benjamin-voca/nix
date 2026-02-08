{ config, lib, pkgs, ... }:

{
  options.services.quadnix.gitea-deploy = {
    enable = lib.mkEnableOption "Deploy Gitea with HA configuration";
    
    replicas = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Number of Gitea replicas for HA";
    };
    
    runnerCount = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Number of Gitea runners to deploy";
    };
    
    postgres = {
      enable = lib.mkEnableOption "Deploy PostgreSQL for Gitea";
      replicas = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Number of PostgreSQL replicas";
      };
    };
    
    redis = {
      enable = lib.mkEnableOption "Deploy Redis for Gitea caching";
      replicas = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Number of Redis replicas";
      };
    };
  };

  config = lib.mkIf config.services.quadnix.gitea-deploy.enable {
    # Gitea chart configuration
    environment.etc."gitea/values.yaml".text = lib.generators.toYAML {} {
      # HA configuration (previous: replicaCount = 2-3 for HA)
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
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
        };
        hosts = [{
          host = "gitea.quadtech.dev";
          paths = [{
            path = "/";
            pathType = "Prefix";
          }];
        }];
        tls = [{
          secretName = "gitea-tls";
          hosts = [ "gitea.quadtech.dev" ];
        }];
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
      
      # PostgreSQL configuration (previous: replicas = 2, primary + standby)
      postgresql = {
        enabled = config.services.quadnix.gitea-deploy.postgres.enable;
        replicas = 1;
        auth = {
          database = "gitea";
          username = "gitea";
          password = "${config.sops.secrets.gitea-db-password.path}";
        };
        primary = {
          persistence = {
            enabled = true;
            size = "10Gi";
          };
        };
        standby = {
          enabled = false;
        };
      };
      
      # Redis configuration (previous: replicas = 2, master + slave)
      redis = {
        enabled = config.services.quadnix.gitea-deploy.redis.enable;
        replicas = 1;
        master = {
          persistence = {
            enabled = true;
            size = "5Gi";
          };
        };
        slave = {
          enabled = false;
        };
      };
      
      # Gitea configuration
      gitea = {
        admin = {
          existingSecret = "gitea-admin";
          username = "gitea_admin";
          email = "admin@quadtech.dev";
        };
        
        config = {
          server = {
            DOMAIN = "gitea.quadtech.dev";
            ROOT_URL = "https://gitea.quadtech.dev";
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
            SSL_MODE = "disable";
          };
          
          cache = {
            ENABLED = true;
            ADAPTER = "redis";
            conn = "redis://gitea-redis-master:6379";
          };
          
          session = {
            PROVIDER = "redis";
            conn = "redis://gitea-redis-master:6379";
          };
          
          queue = {
            TYPE = "redis";
            conn = "redis://gitea-redis-master:6379";
          };
          
          service = {
            DISABLE_REGISTRATION = true;
            REQUIRE_SIGNIN_VIEW = true;
            ENABLE_NOTIFY_MAIL = false;
          };
          
          actions = {
            ENABLED = true;
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
          cpu = "1000m";
          memory = "1Gi";
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
      
      # Node affinity for HA (previous: podAntiAffinity for spreading across nodes)
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
      
      # Tolerations for backbone taints
      tolerations = [
        { key = "role"; operator = "Equal"; value = "backbone"; effect = "NoSchedule"; }
        { key = "infra"; operator = "Equal"; value = "true"; effect = "NoSchedule"; }
      ];
    };

    # Gitea runners configuration
    environment.etc."gitea/runners.yaml".text = lib.generators.toYAML {} {
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: gitea-runner-backbone
        namespace: gitea
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: gitea-runner-backbone
        template:
          metadata:
            labels:
              app: gitea-runner-backbone
          spec:
            nodeSelector:
              role: backbone
            tolerations:
            - key: "role"
              operator: "Equal"
              value: "backbone"
              effect: "NoSchedule"
            serviceAccountName: gitea-runner
            containers:
            - name: runner
              image: gitea/gitea-actions-runner:1.25.4
              env:
              - name: GITEA_INSTANCE_URL
                value: "https://gitea.quadtech.dev"
              - name: GITEA_RUNNER_NAME
                value: "gitea-runner-backbone"
              - name: GITEA_RUNNER_TOKEN
                valueFrom:
                  secretKeyRef:
                    name: gitea-runner-token
                    key: token
              - name: GITEA_RUNNER_LABELS
                value: "ubuntu-latest,linux,x86_64,self-hosted,backbone"
              resources:
                requests:
                  cpu: "500m"
                  memory: "1Gi"
                limits:
                  cpu: "1000m"
                  memory: "2Gi"
    };

    # Gitea ServiceMonitor for Prometheus
    environment.etc."gitea/servicemonitor.yaml".text = lib.generators.toYAML {} {
      apiVersion: monitoring.coreos.com/v1
      kind: ServiceMonitor
      metadata:
        name: gitea
        namespace: gitea
        labels:
          app: gitea
      spec:
        selector:
          matchLabels:
            app: gitea
        endpoints:
        - port: http
          path: /metrics
          interval: 30s
          scrapeTimeout: 10s
    };
  };
}