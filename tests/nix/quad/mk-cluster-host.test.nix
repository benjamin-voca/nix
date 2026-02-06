{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../../modules/options/quad.nix
      ../../../modules/lib/mk-cluster-host.nix
      ({ ... }: {
        _module.args.inputs = {
          nixpkgs = pkgs;
          sops-nix = { nixosModules = { sops = { }; }; };
        };
      })
    ];
  };
in
assert lib.isFunction eval.config.quad.lib.mkClusterHost;
true
