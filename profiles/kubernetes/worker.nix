{ config, pkgs, ... }:

{
  imports = [
    ../../nix/modules/shared/common.nix
    ../../nix/modules/shared/kubernetes-common.nix
    ../../nix/modules/kubernetes/worker.nix
  ];

  services.kubernetes = {
    enable = true;
    worker.enable = true;
  };
}
