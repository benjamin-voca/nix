{ config, pkgs, ... }:

{
  services.kubernetes = {
    enable = true;
    controlPlane.enable = true;
    apiserver.enable = true;
    scheduler.enable = true;
    controllerManager.enable = true;
  };
}
