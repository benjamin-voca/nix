{ config, pkgs, ... }:

{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/sops.nix
    # ../profiles/kubernetes/control-plane.nix  # Disabled for now - complex NixOS K8s setup
    ../profiles/kubernetes/helm.nix
    ../modules/services/cloudflared-k8s.nix
  ];

  networking.firewall.allowedTCPPorts = [
    22 443 6443
  ];

  # Kubernetes disabled for now - will set up properly later
  # services.kubernetes = {
  #   roles = [ "master" ];
  #   masterAddress = "${config.networking.hostName}.local";
  #   
  #   controlPlane.enable = true;
  # };

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
      # SSH access - primary route
      {
        hostname = "mainssh.quadtech.dev";
        service = "ssh://localhost:22";
        originRequest = {
          noTLSVerify = true;
        };
      }

      # Uncomment services below as they become available
      
      # Existing application (edukurs)
      # {
      #   hostname = "edukurs.quadtech.dev";
      #   service = "http://localhost:3000";
      # }

      # Gitea (enable when running)
      # {
      #   hostname = "gitea.quadtech.dev";
      #   service = "http://localhost:8080";
      # }

      # ClickHouse (enable after K8s deployment)
      # {
      #   hostname = "clickhouse.quadtech.dev";
      #   service = "http://localhost:30081";
      # }

      # Grafana (enable after K8s deployment)
      # {
      #   hostname = "grafana.quadtech.dev";
      #   service = "http://localhost:30082";
      # }
    ];

    catchAll = "http_status:404";
    logLevel = "info";
  };
}
