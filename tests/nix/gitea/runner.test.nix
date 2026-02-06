{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  mockEnvironment = {
    options.environment = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
    };
  };
  mockSystemd = {
    options.systemd = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
    };
  };
  eval = lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      mockEnvironment
      mockSystemd
      ../../../modules/shared/quad-common.nix
      ../../../modules/shared/gitea-common.nix
      ../../../modules/gitea/runner.nix
      {
        services.gitea.runner.enable = true;
        services.gitea.runner.tokenFile = builtins.toFile "token" "runner-token";
      }
    ];
  };

  runnerConfig = lib.attrByPath [ "environment" "etc" "gitea/runner/config.yaml" "source" ] null eval.config;
  runnerService = lib.attrByPath [ "systemd" "services" "gitea-runner" "serviceConfig" "ExecStart" ] null eval.config;
in
assert runnerConfig != null;
assert runnerService != null;
true
