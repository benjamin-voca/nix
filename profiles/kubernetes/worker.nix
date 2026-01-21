{ config, pkgs, ... }:

{
  services.kubernetes = {
    enable = true;
    worker.enable = true;
  };
}
