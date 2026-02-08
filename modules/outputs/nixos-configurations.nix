{ config, inputs, ... }:

{
  config.flake.nixosConfigurations = inputs.nixpkgs.lib.mapAttrs (_: host: host) config.quad.hosts;
}
