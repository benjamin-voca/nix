{ helmLib }:

{
  # ArgoCD configuration
  argocd = helmLib.buildChart {
    name = "argocd";
    chart = helmLib.charts.argoproj.argo-cd;
    namespace = "argocd";
    values = {
      global = {
        domain = "argocd.quadtech.dev";
      };

      configs = {
        cm = {
          "server.insecure" = "true";
        };
      };

      # Server configuration
      server = {
        replicas = 1;
        service = {
          type = "ClusterIP";
        };
        ingress = {
          enabled = true;
          ingressClassName = "nginx";
          hostname = "argocd.quadtech.dev";
          tls = false;
        };
      };

      # Redis HA for high availability
      redis-ha = {
        enabled = false;
      };

      # Controller configuration
      controller = {
        replicas = 1;
      };

      # Repo server configuration
      repoServer = {
        replicas = 1;
      };

      # ApplicationSet controller
      applicationSet = {
        enabled = true;
      };

      # Notifications controller
      notifications = {
        enabled = true;
      };

      # Global configuration
      global = {
        image = {
          tag = "v2.9.3";
        };
      };
    };
  };
}
