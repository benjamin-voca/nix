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
    specialArgs = { inherit pkgs; };
    modules = [
      mockEnvironment
      ../../../modules/shared/quad-common.nix
      ../../../modules/shared/kubernetes-common.nix
      ../../../modules/kubernetes/worker.nix
      {
        services.kubernetes.worker.enable = true;
        services.kubernetes.worker.nodeIP = "10.1.0.5";
      }
    ];
  };

  kubeletConfig = lib.attrByPath [ "environment" "etc" "kubernetes/kubelet.yaml" "source" ] null eval.config;
in
assert kubeletConfig != null;
true
