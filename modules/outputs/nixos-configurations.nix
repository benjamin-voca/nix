{ config, lib, ... }:

{
  config.flake.nixosConfigurations = lib.mapAttrs (_: host: host) config.quad.hosts;
}
