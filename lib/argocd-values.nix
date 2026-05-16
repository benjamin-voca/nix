{
  domain ? "argocd.quadtech.dev",
  imageTag ? "v2.9.3",
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
    image.tag = imageTag;
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
    initContainers = [
      {
        name = "copyutil";
        args = [
          "/bin/cp /usr/local/bin/argocd /var/run/argocd/argocd && /bin/ln -sf /var/run/argocd/argocd /var/run/argocd/argocd-cmp-server"
        ];
      }
    ];
  };

  applicationSet = {
    enabled = enableApplicationSet;
  };

  notifications = {
    enabled = enableNotifications;
  };
}
