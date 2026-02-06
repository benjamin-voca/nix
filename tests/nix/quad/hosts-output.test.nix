{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../../modules/options/flake.nix
      ../../../modules/options/quad.nix
      {
        quad.hosts = {
          "backbone-01" = { config = "dummy"; };
          "frontline-01" = { config = "dummy"; };
        };
      }
      ../../../modules/outputs/nixos-configurations.nix
    ];
  };
in
assert (eval.config.flake.nixosConfigurations ? "backbone-01");
assert (eval.config.flake.nixosConfigurations ? "frontline-01");
true
