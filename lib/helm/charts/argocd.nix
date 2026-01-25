{ helmLib }:

{
  # ArgoCD configuration
  argocd = helmLib.buildChart {
    name = "argocd";
    chart = helmLib.charts.argoproj.argo-cd;
    namespace = "argocd";
    values = {
      # Server configuration
      server = {
        replicas = 2;
        service = {
          type = "ClusterIP";
        };
        ingress = {
          enabled = true;
          ingressClassName = "nginx";
          hosts = [
            "argocd.example.com"
          ];
          tls = [{
            secretName = "argocd-tls";
            hosts = [ "argocd.example.com" ];
          }];
        };
      };

      # Redis HA for high availability
      redis-ha = {
        enabled = true;
      };

      # Controller configuration
      controller = {
        replicas = 1;
      };

      # Repo server configuration
      repoServer = {
        replicas = 2;
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
