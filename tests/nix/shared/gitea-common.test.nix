{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../../nix/modules/shared/common.nix
      ../../../nix/modules/shared/gitea-common.nix
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
