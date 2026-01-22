{ config, pkgs, ... }:

{
  services.gitea = {
    enable = true;
    settings = {
      server = {
        DOMAIN = "git.quadtech.dev";
        ROOT_URL = "https://git.quadtech.dev";
        HTTP_PORT = 443;
        SSH_PORT = 2222;
        DISABLE_SSH = false;
      };
      service = {
        DISABLE_REGISTRATION = false;
      };
    };
  };
}
