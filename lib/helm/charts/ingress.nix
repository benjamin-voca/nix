{ helmLib }:

{
  # Ingress NGINX configuration
  ingress-nginx = helmLib.buildChart {
    name = "ingress-nginx";
    chart = helmLib.charts.ingress-nginx.ingress-nginx;
    namespace = "ingress-nginx";
    values = {
      controller = {
        replicaCount = 2;
        
        # Service configuration
        service = {
          type = "LoadBalancer";
          annotations = {
            "service.beta.kubernetes.io/do-loadbalancer-enable-proxy-protocol" = "true";
          };
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
          enabled = true;
          minAvailable = 1;
        };

        # Auto-scaling
        autoscaling = {
          enabled = true;
          minReplicas = 2;
          maxReplicas = 5;
          targetCPUUtilizationPercentage = 80;
          targetMemoryUtilizationPercentage = 80;
        };
      };

      # Default backend
      defaultBackend = {
        enabled = true;
        replicaCount = 2;
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
