{ config, pkgs, ... }:

{
  services.kubernetes = {
    addons = {
      metrics-server.enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    kubectl
  ];
}
