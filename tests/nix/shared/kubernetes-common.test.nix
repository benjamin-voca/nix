{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  mockEnvironment = {
    options.environment = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
    };
  };
  mockKubernetesRoles = {
    options.services.kubernetes.roles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };
  eval = lib.evalModules {
    modules = [
      mockEnvironment
      mockKubernetesRoles
      ../../../modules/shared/quad-common.nix
      ../../../modules/shared/kubernetes-common.nix
      {
        services.kubernetes.roles = [ "master" ];
        services.kubernetes.common.clusterName = "alpha";
      }
    ];
  };

  commonText = lib.attrByPath [ "environment" "etc" "kubernetes/common.json" "text" ] null eval.config;
in
assert commonText != null;
true
