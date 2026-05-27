{
  domain ? "argocd.quadtech.dev",
  serverUrl ? "http://${domain}",
  serverReplicas ? 1,
  controllerReplicas ? 1,
  repoServerReplicas ? 1,
  enableApplicationSet ? true,
  enableNotifications ? true,
}:
{
  global = {
    domain = domain;
  };

  configs = {
    cm = {
      "server.insecure" = true;
      url = serverUrl;
    };
    params = {
      "server.insecure" = true;
    };
    secret = {
      argocdServerAdminPassword = "PLACEHOLDER";
    };
  };

  server = {
    replicas = serverReplicas;
    service = {
      type = "ClusterIP";
    };
    metrics = {
      enabled = true;
      service = {
        type = "ClusterIP";
        port = 8082;
      };
      serviceMonitor = {
        enabled = false;   # ServiceMonitor created in bootstrap instead
      };
    };
  };

  redis = {
    enabled = true;
  };

  "redis-ha" = {
    enabled = false;
  };

  controller = {
    replicas = controllerReplicas;
  };

  repoServer = {
    replicas = repoServerReplicas;
  };

  applicationSet = {
    enabled = enableApplicationSet;
  };

  notifications = {
    enabled = enableNotifications;
  };
}
