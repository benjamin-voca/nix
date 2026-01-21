{ config, pkgs, ... }:

{
  services.gitea = {
    enable = true;
    database.type = "postgres";
    protocol = "https";
  };
}
