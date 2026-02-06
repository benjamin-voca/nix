{ config, inputs, lib, ... }:

let
  deployLib = inputs.deploy-rs.lib.x86_64-linux;
in
{
  config.flake.deploy = {
    nodes = {
      "backbone-01" = {
        hostname = "backbone01";
        profiles.system = {
          user = "root";
          path = deployLib.activate.nixos config.flake.nixosConfigurations.backbone-01;
        };
        sshUser = "root";
        remoteBuild = true;
      };

      "backbone-02" = {
        hostname = "192.168.1.11";
        profiles.system = {
          user = "root";
          path = deployLib.activate.nixos config.flake.nixosConfigurations.backbone-02;
        };
        sshUser = "root";
      };

      "frontline-01" = {
        hostname = "192.168.1.20";
        profiles.system = {
          user = "root";
          path = deployLib.activate.nixos config.flake.nixosConfigurations.frontline-01;
        };
        sshUser = "root";
      };

      "frontline-02" = {
        hostname = "192.168.1.21";
        profiles.system = {
          user = "root";
          path = deployLib.activate.nixos config.flake.nixosConfigurations.frontline-02;
        };
        sshUser = "root";
      };
    };
  };

  config.flake.apps = {
    deploy = inputs.deploy-rs.apps.x86_64-linux.deploy;
  };
}
