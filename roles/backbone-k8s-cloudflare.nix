{ config, pkgs, ... }:

{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/helm.nix
    ../modules/services/cloudflared-k8s.nix
  ];

  # Network configuration
  networking.firewall.allowedTCPPorts = [
    22    # SSH
    443   # HTTPS
    6443  # Kubernetes API
  ];

  # Kubernetes configuration
  services.kubernetes = {
    roles = [ "master" ];
    controlPlane.enable = true;
  };

  # Cloudflare Tunnel configuration for K8s services
  services.cloudflared-k8s = {
    enable = true;
    tunnelId = "9832df66-f04a-40ea-b004-f6f9b100eb14";
    credentialsFile = "/home/klajd/.cloudflared/9832df66-f04a-40ea-b004-f6f9b100eb14.json";

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

      # Gitea (Kubernetes service)
      # After deploying Gitea to K8s, use port-forward or NodePort to expose locally
      {
        hostname = "gitea.quadtech.dev";
        service = "http://localhost:30080";  # NodePort or port-forward
      }

      # ClickHouse (Kubernetes service)
      {
        hostname = "clickhouse.quadtech.dev";
        service = "http://localhost:30081";  # NodePort or port-forward
      }

      # Grafana (Kubernetes service)
      {
        hostname = "grafana.quadtech.dev";
        service = "http://localhost:30082";  # NodePort or port-forward
      }
    ];

    catchAll = "http_status:404";
    logLevel = "info";
  };
}
