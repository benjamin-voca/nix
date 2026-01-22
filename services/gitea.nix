{ config, pkgs, ... }:

{
  imports = [
    ../nix/modules/shared/common.nix
    ../nix/modules/shared/gitea-common.nix
    ../nix/modules/gitea/server.nix
  ];

  services.gitea = {
    enable = true;
    database = {
      type = "postgres";
      host = "postgres.quadtech.dev";
      name = "gitea";
      user = "gitea";
    };
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeysOnly = true;
    };
    backup = {
      enable = true;
      interval = "daily";
      retention = 30;
    };
    migrations.enable = true;
    domain = "git.quadtech.dev";
    rootUrl = "https://git.quadtech.dev";
  };
}
