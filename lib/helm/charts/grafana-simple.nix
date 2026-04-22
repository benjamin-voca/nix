{helmLib}: {
  # Grafana - Single Instance Configuration for Cloudflare Tunnel
  grafana = helmLib.buildChart {
    name = "grafana";
    chart = helmLib.charts.grafana.grafana;
    namespace = "grafana";
    values = {
      # Single replica (no HA)
      replicas = 1;

      # Image configuration
      image = {
        repository = "grafana/grafana";
        tag = "10.2.3";
        pullPolicy = "IfNotPresent";
      };

      # Service configuration - ClusterIP only (Cloudflare Tunnel handles external access)
      service = {
        type = "ClusterIP";
        port = 80;
        targetPort = 3000;
      };

      # Ingress disabled - using Cloudflare Tunnel
      ingress = {
        enabled = false;
      };

      # Persistence
      persistence = {
        enabled = true;
        size = "10Gi";
        storageClassName = "ceph-block";
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
          # Configured via env vars from grafana-db secret
          # GF_DATABASE_TYPE, GF_DATABASE_HOST, GF_DATABASE_NAME, GF_DATABASE_USER, GF_DATABASE_PASSWORD
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
          # Secret key and admin password should be set via env vars/secrets, not values
          # GF_SECURITY_SECRET_KEY, GF_SECURITY_ADMIN_PASSWORD
          assertNoLeakedSecrets = false;
        };

        snapshots = {
          external_enabled = true;
        };

        "log" = {
          mode = "console";
          level = "info";
        };

        plugins = {
          allow_loading_unsigned_plugins = "grafana-clickhouse-datasource";
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
          providers = [
            {
              name = "default";
              orgId = 1;
              folder = "";
              type = "file";
              disableDeletion = false;
              editable = true;
              options = {
                path = "/var/lib/grafana/dashboards/default";
              };
            }
          ];
        };
      };

      # PostgreSQL for Grafana database
      # Disable built-in postgresql — using CNPG shared-pg cluster instead
      postgresql = {
        enabled = false;
      };

      # Resource limits (reduced for single instance)
      resources = {
        requests = {
          cpu = "100m";
          memory = "256Mi";
        };
        limits = {
          cpu = "500m";
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

      # Inject DB credentials from the grafana-db secret
      envFromSecret = "grafana-db";
    };
  };

  # Loki for log aggregation - Single Instance
  loki = helmLib.buildChart {
    name = "loki";
    chart = helmLib.charts.grafana.loki;
    namespace = "loki";
    values = {
      # Loki configuration
      loki = {
        auth_enabled = false;

        commonConfig = {
          replication_factor = 1; # Single instance
        };

        storage = {
          type = "filesystem";
        };

        schemaConfig = {
          configs = [
            {
              from = "2024-01-01";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v12";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
        };
      };

      # Single binary deployment (simplest)
      deploymentMode = "SingleBinary";

      # Single binary configuration
      singleBinary = {
        replicas = 1;
        persistence = {
          enabled = true;
          size = "50Gi";
        };
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

  # Tempo for distributed tracing - Single Instance
  tempo = helmLib.buildChart {
    name = "tempo";
    chart = helmLib.charts.grafana.tempo;
    namespace = "tempo";
    values = {
      # Tempo configuration
      tempo = {
        replicas = 1; # Single instance

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
