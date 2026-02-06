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
      ../../../modules/kubernetes/control-plane.nix
      {
        services.kubernetes.controlPlane.enable = true;
        services.kubernetes.controlPlane.etcd.enable = true;
        services.kubernetes.controlPlane.apiServer.enable = true;
        services.kubernetes.controlPlane.apiServer.advertiseAddress = "10.0.0.1";
        services.kubernetes.controlPlane.etcd.cluster = [ "https://etcd-0:2379" ];
      }
    ];
  };

  apiServer = lib.attrByPath [ "environment" "etc" "kubernetes/api-server.yaml" "source" ] null eval.config;
  etcdConf = lib.attrByPath [ "environment" "etc" "kubernetes/etcd.conf" "source" ] null eval.config;
in
assert apiServer != null;
assert etcdConf != null;
true
