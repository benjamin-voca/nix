{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  mockEnvironment = {
    options.environment = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
    };
  };
  eval = lib.evalModules {
    modules = [
      mockEnvironment
      ../../../modules/shared/quad-common.nix
      {
        quad.environment = "staging";
        quad.versions.kubernetes = "1.28.1";
        quad.paths.stateDir = "/data/quadnix";
      }
    ];
  };

  envText = lib.attrByPath [ "environment" "etc" "quadnix/environment" "text" ] null eval.config;
  versionsText = lib.attrByPath [ "environment" "etc" "quadnix/versions.json" "text" ] null eval.config;
in
assert envText == "staging";
assert versionsText != null;
true
