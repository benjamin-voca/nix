# machines/consumer.nix — Machine Registry → NixOS Module Bridge
#
# Reads the machine registry from machines/default.nix and produces
# config.quad.hosts entries using mkClusterHost.
#
# Phase 1: Created but NOT imported. Will be wired in Phase 2
# via modules/imports.nix (replacing filesIn ./hosts with this file).
#
{ config, inputs, ... }:

let
  registry = import ./default.nix;
  mkHost = name: machineDef:
    let
      roleDef = registry.roles.${machineDef.role}
        or (throw "Machine '${name}' references unknown role '${machineDef.role}'. Available roles: ${builtins.concatStringsSep ", " (builtins.attrNames registry.roles)}");
    in
    config.quad.lib.mkClusterHost {
      inherit (machineDef) system;
      inherit name;
      hardwareModule = machineDef.hardware;
      roleModule = roleDef.module;
      taints = machineDef.taints or [];
      extraModules = machineDef.extraModules or [];
      sshHost = machineDef.sshHost or name;
      remoteBuild = machineDef.remoteBuild or false;
    };
in
{
  config.quad.hosts = builtins.mapAttrs mkHost registry.machines;
}
