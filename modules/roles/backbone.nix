{ config, pkgs, ... }:

{
  imports = [
    ../profiles/base.nix
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/sops.nix
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/allow-master-workloads.nix
    ../profiles/kubernetes/helm.nix
    ../services/cloudflared-k8s.nix
  ];

  networking.firewall.allowedTCPPorts = [
    22 443 6443
  ];

  sops.secrets = {
    cloudflared-credentials = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/cloudflared-credentials.json";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    gitea-db-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    };
    infisical-db-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    };
    infisical-encryption-key = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    };
    infisical-auth-secret = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    };
  };


  services.cloudflared-k8s = {
    enable = true;
    tunnelId = "b6bac523-be70-4625-8b67-fa78a9e1c7a5";
    credentialsFile = config.sops.secrets.cloudflared-credentials.path;
    wildcardHostname = "*.quadtech.dev";

    routes = [
      {
        hostname = "mainssh.quadtech.dev";
        service = "ssh://localhost:22";
      }
    ];

    catchAll = "http_status:404";
    logLevel = "info";
  };
}
