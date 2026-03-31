{ helmLib }:

{
  # Prometheus configuration using kube-prometheus-stack
  prometheus = helmLib.buildChart {
    name = "monitoring";
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
                storageClassName = "ceph-block";
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
          hosts = [ "grafana.k8s.quadtech.dev" ];
          tls = [{
            secretName = "grafana-tls";
            hosts = [ "grafana.k8s.quadtech.dev" ];
          }];
        };
        persistence = {
          enabled = true;
          size = "10Gi";
          storageClassName = "ceph-block";
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
                storageClassName = "ceph-block";
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
