{ inputs, config, ... }:

let
  lib = inputs.nixpkgs.lib;
  mkClusterHost =
    { name
    , system
    , hardwareModule
    , roleModule
    , serviceModules ? [ ]
    , extraModules ? [ ]
    , taints ? [ ]
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules =
        [
          inputs.sops-nix.nixosModules.sops
          ({ ... }: { networking.hostName = name; })
          ({ pkgs, ... }: {
            system.stateVersion = "26.05";
            programs.fish.enable = true;
            users.users.root.shell = pkgs.fish;
            networking.domain = "local";
            networking.fqdn = "${name}.local";
            systemd.services.dhcpcd.restartIfChanged = false;
            systemd.services.dhcpcd.reloadIfChanged = false;
            systemd.services.dhcpcd.stopIfChanged = false;
            
            # Apply taints if any
            systemd.services.kubelet.serviceConfig = {
Environment = [ "KUBELET_EXTRA_ARGS=--register-with-taints=${toString (lib.concatMapStringsSep "," (taint: "${taint.key}=${taint.value}:${taint.effect}") taints)}" ];
            };
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
