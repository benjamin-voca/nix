{ config, pkgs, ... }:

{
  disabledModules = [ "services/misc/gitea.nix" ];
  services.gitea.enable = true;
}
