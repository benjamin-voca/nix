{ config, pkgs, ... }:

{
  # Install Kubernetes tools
  # Note: Helm charts are managed via Nix flakes (lib/helm/)
  # not as NixOS services
  
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
  ];
}
