{ helmLib }:

{
  # Prometheus configuration using kube-prometheus-stack
  prometheus = helmLib.buildChart {
    name = "prometheus";
    chart = helmLib.charts.prometheus-community.kube-prometheus-stack;
    namespace = "monitoring";
    values = {
      # Prometheus configuration
      prometheus = {
        prometheusSpec = {
          replicas = 2;
          retention = "30d";
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = [ "ReadWriteOnce" ];
                resources = {
                  requests = {
                    storage = "50Gi";
                  };
                };
              };
            };
          };
          # Resource limits
          resources = {
            requests = {
              cpu = "500m";
              memory = "2Gi";
            };
            limits = {
              cpu = "2000m";
              memory = "4Gi";
            };
          };
        };
      };

      # Grafana configuration
      grafana = {
        enabled = true;
        adminPassword = "changeme"; # Should be overridden with secrets
        ingress = {
          enabled = true;
          ingressClassName = "nginx";
          hosts = [ "grafana.example.com" ];
          tls = [{
            secretName = "grafana-tls";
            hosts = [ "grafana.example.com" ];
          }];
        };
        persistence = {
          enabled = true;
          size = "10Gi";
        };
      };

      # Alertmanager configuration
      alertmanager = {
        enabled = true;
        alertmanagerSpec = {
          replicas = 2;
          storage = {
            volumeClaimTemplate = {
              spec = {
                accessModes = [ "ReadWriteOnce" ];
                resources = {
                  requests = {
                    storage = "10Gi";
                  };
                };
              };
            };
          };
        };
      };

      # Node exporter
      nodeExporter = {
        enabled = true;
      };

      # Kube state metrics
      kubeStateMetrics = {
        enabled = true;
      };
    };
  };
}
