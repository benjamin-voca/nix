{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../../nix/modules/shared/common.nix
      ../../../nix/modules/shared/gitea-common.nix
      ../../../nix/modules/gitea/runner.nix
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
