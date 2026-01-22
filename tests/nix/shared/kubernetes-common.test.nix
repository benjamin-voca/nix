{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../../nix/modules/shared/common.nix
      ../../../nix/modules/shared/kubernetes-common.nix
      {
        services.kubernetes.enable = true;
        services.kubernetes.common.clusterName = "alpha";
      }
    ];
  };

  commonText = lib.attrByPath [ "environment" "etc" "kubernetes/common.json" "text" ] null eval.config;
in
assert commonText != null;
true
