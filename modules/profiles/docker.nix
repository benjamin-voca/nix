{pkgs, ...}: {
  environment.systemPackages = with pkgs; [docker];

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    daemon.settings = {
      insecure-registries = [
        "harbor.quadtech.dev"
        "10.0.0.56:5000"
      ];
    };
  };
}
