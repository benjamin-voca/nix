# Backbone Role - Internal Infrastructure Services
#
# Two deployment options:
#
# Option 1: Run services directly on NixOS (simpler, single-node)
#   - Gitea as systemd service
#   - ClickHouse as systemd service
#   - Grafana as systemd service
#   - Good for: Testing, single-server setups, simpler deployments
#
# Option 2: Run services on Kubernetes (HA, scalable, production)
#   - Services deployed as Helm charts
#   - High availability with multiple replicas
#   - Better resource management and scaling
#   - Good for: Production, multi-node clusters, client separation
#
# Choose your option by uncommenting the appropriate imports below.

{ config, pkgs, ... }:

{
  # ============================================================================
  # OPTION 1: NixOS Services (Direct on Host)
  # Uncomment these to run services directly on the NixOS host
  # ============================================================================
  
  # imports = [
  #   ../profiles/server.nix
  #   ../profiles/docker.nix
  #   ../services/gitea.nix       # Gitea as systemd service
  #   ../services/clickhouse.nix  # ClickHouse as systemd service
  #   # Add Grafana service when available
  # ];

  # ============================================================================
  # OPTION 2: Kubernetes-based Services (Recommended for Production)
  # Uncomment these to run services on Kubernetes
  # ============================================================================
  
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/control-plane.nix  # Kubernetes control plane
    ../profiles/kubernetes/helm.nix            # Helm support
  ];

  # Enable Kubernetes control plane
  services.kubernetes = {
    roles = [ "master" ];
    controlPlane = {
      enable = true;
      etcd.enable = true;
      apiServer.enable = true;
      scheduler.enable = true;
      controllerManager.enable = true;
    };
  };

  # ============================================================================
  # Network Configuration
  # ============================================================================
  
  networking.firewall.allowedTCPPorts = [
    22       # SSH
    443      # HTTPS
    3000     # Gitea HTTP (if using NixOS service)
    2222     # Gitea SSH (if using NixOS service)
    6443     # Kubernetes API server
    2379     # etcd client
    2380     # etcd peer
    10250    # kubelet API
    10251    # kube-scheduler
    10252    # kube-controller-manager
  ];

  # ============================================================================
  # Management Tools
  # ============================================================================
  
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s  # Kubernetes TUI for cluster management
  ];
}
