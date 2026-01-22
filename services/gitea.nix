{ config, pkgs, ... }:

{
  services.gitea = {
    enable = true;
    database.type = "postgres";
    domain = "git.quadtech.dev";
    rootUrl = "https://git.quadtech.dev";
  };
}
