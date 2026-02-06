{ config, lib, pkgs, ... }:

{
  imports = [
    ../../shared/quad-common.nix
  ];

  environment.systemPackages = with pkgs; [
    kubernetes
    kubectl
    kubeadm
    cri-tools
    containerd
  ];

  services.kubernetes = {
    roles = [ "master" "node" ];
    masterAddress = config.networking.hostName;
    easyCerts = true;
    apiserverAddress = "0.0.0.0";
  };

  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
    };
  };
}
