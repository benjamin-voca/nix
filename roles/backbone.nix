{ config, pkgs, ... }:

{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/sops.nix
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/helm.nix
    ../modules/services/cloudflared-k8s.nix
  ];

  networking.firewall.allowedTCPPorts = [
    22 443 6443
  ];

  services.kubernetes = {
    roles = [ "master" ];
    masterAddress = "${config.networking.hostName}.local";
    
    controlPlane.enable = true;
  };

  # SOPS secrets configuration
  sops.secrets = {
    cloudflared-credentials = {
      sopsFile = ../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/cloudflared-credentials.json";
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  # Cloudflare Tunnel configuration for K8s services
  services.cloudflared-k8s = {
    enable = true;
    tunnelId = "9832df66-f04a-40ea-b004-f6f9b100eb14";
    
    # Use SOPS-managed credentials
    credentialsFile = config.sops.secrets.cloudflared-credentials.path;

    routes = [
      # Existing application (edukurs)
      {
        hostname = "edukurs.quadtech.dev";
        service = "http://localhost:3000";
      }

      # SSH access
      {
        hostname = "ssh.quadtech.dev";
        service = "ssh://localhost:22";
      }

      # Gitea - currently on NixOS service, will move to K8s
      {
        hostname = "gitea.quadtech.dev";
        service = "http://localhost:8080";  # Change to 30080 after K8s deployment
      }

      # ClickHouse (Kubernetes service - deploy first)
      {
        hostname = "clickhouse.quadtech.dev";
        service = "http://localhost:30081";
      }

      # Grafana (Kubernetes service - deploy first)
      {
        hostname = "grafana.quadtech.dev";
        service = "http://localhost:30082";
      }
    ];

    catchAll = "http_status:404";
    logLevel = "info";
  };
}
