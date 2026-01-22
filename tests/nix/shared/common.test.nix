{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../../nix/modules/shared/common.nix
      {
        quadnix.environment = "staging";
        quadnix.versions.kubernetes = "1.28.1";
        quadnix.paths.stateDir = "/data/quadnix";
      }
    ];
  };

  envText = lib.attrByPath [ "environment" "etc" "quadnix/environment" "text" ] null eval.config;
  versionsText = lib.attrByPath [ "environment" "etc" "quadnix/versions.json" "text" ] null eval.config;
in
assert envText == "staging";
assert versionsText != null;
true
