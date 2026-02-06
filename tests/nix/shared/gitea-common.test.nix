{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  mockEnvironment = {
    options.environment = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
    };
  };
  mockGitea = {
    options.services.gitea.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };
  eval = lib.evalModules {
    modules = [
      mockEnvironment
      mockGitea
      ../../../modules/shared/quad-common.nix
      ../../../modules/shared/gitea-common.nix
      {
        services.gitea.enable = true;
        services.gitea.common.stateDir = "/data/gitea";
      }
    ];
  };

  commonText = lib.attrByPath [ "environment" "etc" "gitea/conf/common.json" "text" ] null eval.config;
in
assert commonText != null;
true
