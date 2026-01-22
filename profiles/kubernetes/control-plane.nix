{ config, pkgs, ... }:

{
  imports = [
    ../../nix/modules/shared/common.nix
    ../../nix/modules/shared/kubernetes-common.nix
    ../../nix/modules/kubernetes/control-plane.nix
  ];

  services.kubernetes.controlPlane = {
      enable = true;
      etcd.enable = true;
      apiServer.enable = true;
      scheduler.enable = true;
      controllerManager.enable = true;
    };
}
