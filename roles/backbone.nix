{ config, pkgs, ... }:

{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/helm.nix
  ];

  networking.firewall.allowedTCPPorts = [
    22 443 6443
  ];

  services.kubernetes = {
    roles = [ "master" ];
    controlPlane.enable = true;
  };
}
