{ config, pkgs, ... }:

{
  imports = [ sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      # Add secrets here following the pattern:
      # "path/to/secret" = {};
    };
  };
}
