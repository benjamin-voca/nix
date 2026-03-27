{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [ docker ];

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    daemon.settings = {
      insecure-registries = [
        "harbor.quadtech.dev"
      ];
    };
  };
}
