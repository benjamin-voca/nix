{ config, lib, pkgs, ... }:

{
  options.services.quadnix.grafana-deploy = {
    enable = lib.mkEnableOption "Deploy Grafana with HA configuration";
    
    replicas = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Number of Grafana replicas for HA";
    };
    
    postgres = {
      enable = lib.mkEnableOption "Deploy PostgreSQL for Grafana";
      replicas = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Number of PostgreSQL replicas";
      };
    };
  };

  config = lib.mkIf config.services.quadnix.grafana-deploy.enable {
    # Grafana chart configuration
    environment.etc."grafana/values.yaml".text = lib.generators.toYAML {} {
      # HA configuration
      replicas = 1;
      
      # Image configuration
      image = {
        repository = "grafana/grafana";
        tag = "10.2.3";
        pullPolicy = "IfNotPresent";
      };
      
      # Service configuration
      service = {
        type = "ClusterIP";
        port = 80;
        targetPort = 3000;
      };
      
      # Ingress configuration
      ingress = {
        enabled = true;
        ingressClassName = "nginx";
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
          "nginx.ingress.kubernetes.io/proxy-body-size" = "50m";
        };
        hosts = [{
          host = "grafana.quadtech.dev";
          paths = [{
            path = "/";
            pathType = "Prefix";
          }];
        }];
        tls = [{
          secretName = "grafana-tls";
          hosts = [ "grafana.quadtech.dev" ];
        }];
      };
      
      # Persistence
      persistence = {
        enabled = true;
        size = "10Gi";
        storageClassName = "local-path";
      };
      
      # PostgreSQL configuration
      postgresql = {
        enabled = config.services.quadnix.grafana-deploy.postgres.enable;
        auth = {
          database = "grafana";
          username = "grafana";
          password = "${config.sops.secrets.grafana-db-password.path}";
        };
        primary = {
          persistence = {
            enabled = true;
            size = "5Gi";
          };
        };
        standby = {
          enabled = false;
        };
      };
      
      # Grafana configuration
      "grafana.ini" = {
        server = {
          root_url = "https://grafana.quadtech.dev";
          domain = "grafana.quadtech.dev";
        };
        
        database = {
          type = "postgres";
          host = "grafana-postgresql:5432";
          name = "grafana";
          user = "grafana";
        };
        
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
        };
        
        users = {
          allow_sign_up = false;
          auto_assign_org = true;
          auto_assign_org_role = "Viewer";
        };
        
        auth = {
          disable_login_form = false;
        };
        
        "auth.anonymous" = {
          enabled = false;
        };
        
        security = {
          secret_key = "${config.sops.secrets.grafana-secret-key.path}";
          admin_user = "admin";
          admin_password = "${config.sops.secrets.grafana-admin-password.path}";
        };
        
        snapshots = {
          external_enabled = true;
        };
        
        dashboards = {
          default_home_dashboard_path = "/var/lib/grafana/dashboards/default/home.json";
        };
        
        "log" = {
          mode = "console";
          level = "info";
        };
        
        metrics = {
          enabled = true;
        };
      };
      
      # Data sources
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1;
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url = "http://prometheus-kube-prometheus-prometheus.monitoring:9090";
              access = "proxy";
              isDefault = true;
              editable = true;
            }
            {
              name = "Loki";
              type = "loki";
              url = "http://loki.loki:3100";
              access = "proxy";
              editable = true;
            }
            {
              name = "ClickHouse";
              type = "clickhouse";
              url = "http://clickhouse.clickhouse:8123";
              access = "proxy";
              editable = true;
              jsonData = {
                defaultDatabase = "default";
              };
            }
          ];
        };
      };
      
      # Dashboard providers
      dashboardProviders = {
        "dashboardproviders.yaml" = {
          apiVersion = 1;
          providers = [{
            name = "default";
            orgId = 1;
            folder = "";
            type = "file";
            disableDeletion = false;
            editable = true;
            options = {
              path = "/var/lib/grafana/dashboards/default";
            };
          }];
        };
      };
      
      # Resource limits
      resources = {
        requests = {
          cpu = "100m";
          memory = "256Mi";
        };
        limits = {
          cpu = "1000m";
          memory = "1Gi";
        };
      };
      
      # Probes
      livenessProbe = {
        httpGet = {
          path = "/api/health";
          port = 3000;
        };
        initialDelaySeconds = 60;
        periodSeconds = 10;
        timeoutSeconds = 5;
        failureThreshold = 10;
      };
      
      readinessProbe = {
        httpGet = {
          path = "/api/health";
          port = 3000;
        };
        initialDelaySeconds = 10;
        periodSeconds = 5;
        timeoutSeconds = 3;
      };
      
      # Security context
      podSecurityContext = {
        fsGroup = 472;
        runAsUser = 472;
        runAsGroup = 472;
      };
      
      # Service monitor for Prometheus
      serviceMonitor = {
        enabled = true;
        interval = "30s";
        scrapeTimeout = "10s";
      };
      
      # Sidecar for dashboard/datasource auto-loading
      sidecar = {
        dashboards = {
          enabled = true;
          label = "grafana_dashboard";
          labelValue = "1";
          folder = "/tmp/dashboards";
          folderAnnotation = "grafana_folder";
          provider = {
            foldersFromFilesStructure = true;
          };
        };
        datasources = {
          enabled = true;
          label = "grafana_datasource";
          labelValue = "1";
        };
      };
      
      # Plugins
      plugins = [
        "grafana-clock-panel"
        "grafana-piechart-panel"
        "grafana-worldmap-panel"
        "grafana-clickhouse-datasource"
      ];
      
      # Pod disruption budget
      podDisruptionBudget = {
        enabled = true;
        minAvailable = 1;
      };
      
      # Anti-affinity for HA
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

    # Grafana ServiceMonitor for Prometheus
    environment.etc."grafana/servicemonitor.yaml".text = lib.generators.toYAML {} {
      apiVersion: monitoring.coreos.com/v1
      kind: ServiceMonitor
      metadata:
        name: grafana
        namespace: grafana
        labels:
          app: grafana
      spec:
        selector:
          matchLabels:
            app: grafana
        endpoints:
        - port: http
          path: /metrics
          interval: 30s
          scrapeTimeout: 10s
    };
  };
}