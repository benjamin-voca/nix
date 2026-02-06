{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  mockEnvironment = {
    options.environment = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
    };
  };
  mockNetworking = {
    options.networking = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
  };
  mockServices = {
    options.services = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
  };
  mockVirtualisation = {
    options.virtualisation = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
  };
  eval = lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      mockEnvironment
      mockNetworking
      mockServices
      mockVirtualisation
      ../../../modules/profiles/kubernetes/control-plane.nix
      { networking.hostName = "backbone-01"; }
    ];
  };
in
assert (eval.config.services.kubernetes.roles == [ "master" "node" ]);
true
