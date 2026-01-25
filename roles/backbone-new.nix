# Updated Backbone Role - Internal Services
#
# This role configures backbone nodes to run internal infrastructure services:
# - Kubernetes control plane
# - Gitea (git service)
# - ClickHouse (analytics/logging database)
# - Grafana (observability dashboard)
# - Prometheus (monitoring)
#
# These services run on Kubernetes using Helm charts for declarative management.

{ config, pkgs, ... }:

{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/helm.nix
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

  # Network configuration for control plane
  networking.firewall.allowedTCPPorts = [
    22       # SSH
    443      # HTTPS
    6443     # Kubernetes API
    2379     # etcd client
    2380     # etcd peer
    10250    # kubelet
    10251    # kube-scheduler
    10252    # kube-controller-manager
  ];

  # Install kubectl and helm for management
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s  # Kubernetes TUI
  ];
}
