{ config, inputs, ... }:

let
  mkClusterHost =
    { name
    , system
    , hardwareModule
    , roleModule
    , serviceModules ? [ ]
    , extraModules ? [ ]
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules =
        [
          inputs.sops-nix.nixosModules.sops
          ({ ... }: { networking.hostName = name; })
          ({ pkgs, ... }: {
            system.stateVersion = "26.05";
            programs.fish.enable = true;
            users.users.root.shell = pkgs.fish;
          })
          hardwareModule
          roleModule
        ]
        ++ serviceModules
        ++ extraModules;
    };
in
{
  config.quad.lib.mkClusterHost = mkClusterHost;
}
