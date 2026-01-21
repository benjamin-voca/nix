{ config, pkgs, ... }:

{
  services.kubernetes = {
    helm = {
      enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    kubectl
    helm
  ];
}
