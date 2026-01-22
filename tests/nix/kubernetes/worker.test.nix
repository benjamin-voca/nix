{ pkgs ? import <nixpkgs> {} }:

let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      ../../nix/modules/shared/common.nix
      ../../nix/modules/shared/kubernetes-common.nix
      ../../nix/modules/kubernetes/worker.nix
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
