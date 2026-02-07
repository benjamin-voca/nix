{ helmLib }:

{
  # Ingress NGINX configuration
  ingress-nginx = helmLib.buildChart {
    name = "ingress-nginx";
    chart = helmLib.kubelib.downloadHelmChart {
      repo = "https://kubernetes.github.io/ingress-nginx";
      chart = "ingress-nginx";
      version = "4.14.3";
      chartHash = "sha256-dBFf0R8UHfAQEc2tVLdj6044GRHKFvsOuWbtFsoi4t0=";
    };
    namespace = "ingress-nginx";
    values = {
      controller = {
        replicaCount = 1;
        
        # Service configuration
        service = {
          type = "ClusterIP";
        };

        # Resource limits
        resources = {
          requests = {
            cpu = "100m";
            memory = "128Mi";
          };
          limits = {
            cpu = "500m";
            memory = "512Mi";
          };
        };

        # Metrics
        metrics = {
          enabled = true;
          serviceMonitor = {
            enabled = true;
          };
        };

        # Pod disruption budget
        podDisruptionBudget = {
          enabled = false;
        };

        # Auto-scaling
        autoscaling = {
          enabled = false;
        };
      };

      # Default backend
      defaultBackend = {
        enabled = true;
        replicaCount = 1;
      };
    };
  };

  # Cert-manager configuration
  cert-manager = helmLib.buildChart {
    name = "cert-manager";
    chart = helmLib.charts.jetstack.cert-manager;
    namespace = "cert-manager";
    values = {
      installCRDs = true;

      # Resource limits
      resources = {
        requests = {
          cpu = "10m";
          memory = "32Mi";
        };
        limits = {
          cpu = "100m";
          memory = "128Mi";
        };
      };

      # Webhook configuration
      webhook = {
        resources = {
          requests = {
            cpu = "10m";
            memory = "32Mi";
          };
          limits = {
            cpu = "100m";
            memory = "128Mi";
          };
        };
      };

      # CA injector configuration
      cainjector = {
        resources = {
          requests = {
            cpu = "10m";
            memory = "32Mi";
          };
          limits = {
            cpu = "100m";
            memory = "128Mi";
          };
        };
      };

      # Prometheus metrics
      prometheus = {
        enabled = true;
        servicemonitor = {
          enabled = true;
        };
      };
    };
  };
}
