{pkgs, ...}: let
  d = import ../../lib/domain.nix;
in {
  environment.systemPackages = with pkgs; [docker];

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    daemon.settings = {
      insecure-registries = [
        (d.host "harbor")
        "10.0.0.56:5000"
      ];
    };
  };
}
