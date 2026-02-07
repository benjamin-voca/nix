{ config, pkgs, ... }:

{
  imports = [
    ../../shared/quad-common.nix
  ];

  environment.systemPackages = with pkgs; [
    kubernetes
    kubectl
    cri-tools
    containerd
  ];

  services.kubernetes = {
    roles = [ "node" ];
  };

  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
    };
  };
}
