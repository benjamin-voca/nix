{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [ docker ];

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
}
