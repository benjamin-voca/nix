# machines/consumer.nix — Machine Registry → NixOS Module Bridge
#
# Reads the machine registry from machines/default.nix and produces
# config.quad.hosts entries using mkClusterHost.
#
# Typed secrets: validates required secrets at compile time and generates
# sops.secrets entries automatically from layered SOPS files.
#
{ config, inputs, ... }:

let
  registry = import ./default.nix;
  ts = import ../lib/typed-secrets.nix { inherit (inputs.nixpkgs) lib; };

  # Build secrets config for a machine from its layered files.
  # Returns an attrset suitable for sops.secrets, or {} if no secrets needed.
  buildSecretsConfig = machineName: machineDef: let
    roleDef = registry.roles.${machineDef.role}
      or (throw "Machine '${machineName}' references unknown role '${machineDef.role}'");

    # Read all layered files as {path, content} pairs
    fieldsFiles = builtins.map ts.readSopsContent machineDef.secrets.files;

    # Validate required secrets exist (compile-time check)
    validated = ts.validateRequired roleDef.requiredSecrets fieldsFiles;

    # Convert to sops.secrets format
    secretsAttrset = ts.toSopsSecrets validated;
  in secretsAttrset;

  mkHost = name: machineDef:
    let
      roleDef = registry.roles.${machineDef.role}
        or (throw "Machine '${name}' references unknown role '${machineDef.role}'. Available roles: ${builtins.concatStringsSep ", " (builtins.attrNames registry.roles)}");
      secretsConfig = buildSecretsConfig name machineDef;

      # Build secret module (only if there are secrets)
      secretModule = if secretsConfig == {} then [] else [
        ({ lib, ... }: {
          sops.secrets = secretsConfig;
        })
      ];
    in
    config.quad.lib.mkClusterHost {
      inherit (machineDef) system;
      inherit name;
      hardwareModule = machineDef.hardware;
      roleModule = roleDef.module;
      taints = machineDef.taints or [];
      extraModules = (machineDef.extraModules or []) ++ secretModule;
      sshHost = machineDef.sshHost or name;
      remoteBuild = machineDef.remoteBuild or false;
    };
in
{
  config.quad.hosts = builtins.mapAttrs mkHost registry.machines;
}
