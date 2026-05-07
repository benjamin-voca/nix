{
  config,
  inputs,
  lib,
  ...
}: let
  deployLib = inputs.deploy-rs.lib.x86_64-linux;
in {
  config.flake.deploy = {
    nodes =
      lib.mapAttrs (
        name: host: {
          hostname =
            if host ? _quad && host._quad ? sshHost
            then host._quad.sshHost
            else name;
          profiles.system = {
            user = "root";
            path = deployLib.activate.nixos host;
          };
          sshUser = "root";
          remoteBuild =
            if host ? _quad && host._quad ? remoteBuild
            then host._quad.remoteBuild
            else false;
        }
      )
      config.flake.nixosConfigurations;
  };

  config.flake.apps = {
    deploy = inputs.deploy-rs.apps.x86_64-linux.deploy;
  };
}
