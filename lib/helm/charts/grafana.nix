{ helmLib }:

{
  # Grafana standalone configuration
  grafana = helmLib.buildChart {
    name = "grafana";
    chart = helmLib.charts.grafana.grafana;
    namespace = "grafana";
    values = {
      # Replicas for HA
      replicas = 2;

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

      # Admin credentials (should be managed via secrets)
      adminUser = "admin";
      adminPassword = "changeme";

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
          # Password from secret
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
          # Should be set via secret
          secret_key = "changeme";
          admin_user = "admin";
          admin_password = "changeme";
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

      # PostgreSQL for Grafana database
      postgresql = {
        enabled = true;
        auth = {
          database = "grafana";
          username = "grafana";
          password = "changeme";
        };
        primary = {
          persistence = {
            enabled = true;
            size = "5Gi";
          };
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

      # Plugins to install
      plugins = [
        "grafana-clock-panel"
        "grafana-piechart-panel"
        "grafana-worldmap-panel"
        "grafana-clickhouse-datasource"
      ];

      # Environment variables
      env = {
        GF_INSTALL_PLUGINS = "grafana-clickhouse-datasource";
      };

      # Pod disruption budget
      podDisruptionBudget = {
        minAvailable = 1;
      };

      # Anti-affinity for HA
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [{
            weight = 100;
            podAffinityTerm = {
              labelSelector = {
                matchExpressions = [{
                  key = "app.kubernetes.io/name";
                  operator = "In";
                  values = [ "grafana" ];
                }];
              };
              topologyKey = "kubernetes.io/hostname";
            };
          }];
        };
      };
    };
  };

  # Loki for log aggregation (pairs well with Grafana)
  loki = helmLib.buildChart {
    name = "loki";
    chart = helmLib.charts.grafana.loki;
    namespace = "loki";
    values = {
      # Loki configuration
      loki = {
        auth_enabled = false;
        
        commonConfig = {
          replication_factor = 2;
        };

        storage = {
          type = "filesystem";
        };

        schemaConfig = {
          configs = [{
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v12";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }];
        };
      };

      # Deployment mode (single binary, simple scalable, or distributed)
      deploymentMode = "SimpleScalable";

      # Backend (read/write components)
      backend = {
        replicas = 2;
        persistence = {
          enabled = true;
          size = "50Gi";
        };
      };

      # Read component
      read = {
        replicas = 2;
      };

      # Write component
      write = {
        replicas = 2;
        persistence = {
          enabled = true;
          size = "50Gi";
        };
      };

      # Gateway
      gateway = {
        enabled = true;
        replicas = 2;
      };

      # Monitoring
      monitoring = {
        selfMonitoring = {
          enabled = true;
          grafanaAgent = {
            installOperator = false;
          };
        };
        serviceMonitor = {
          enabled = true;
        };
      };
    };
  };

  # Tempo for distributed tracing (optional, pairs with Grafana)
  tempo = helmLib.buildChart {
    name = "tempo";
    chart = helmLib.charts.grafana.tempo;
    namespace = "tempo";
    values = {
      # Tempo configuration
      tempo = {
        replicas = 2;
        
        storage = {
          trace = {
            backend = "local";
            local = {
              path = "/var/tempo/traces";
            };
          };
        };

        receivers = {
          jaeger = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:14250";
              };
              thrift_http = {
                endpoint = "0.0.0.0:14268";
              };
            };
          };
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317";
              };
              http = {
                endpoint = "0.0.0.0:4318";
              };
            };
          };
        };
      };

      # Persistence
      persistence = {
        enabled = true;
        size = "30Gi";
      };

      # Service monitor
      serviceMonitor = {
        enabled = true;
      };
    };
  };
}
