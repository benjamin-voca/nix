{ config, lib, ... }:

let
  inherit (lib) mkOption mkIf types;
  cfg = config.services.kubernetes.common;
in {
  options.services.kubernetes.common = {
    clusterName = mkOption {
      type = types.str;
      default = "quadnix";
      description = "Logical cluster name for Kubernetes components.";
    };

    serviceCIDR = mkOption {
      type = types.str;
      default = "10.96.0.0/12";
      description = "Service CIDR for Kubernetes services.";
    };

    podCIDR = mkOption {
      type = types.str;
      default = "10.244.0.0/16";
      description = "Pod CIDR for cluster networking.";
    };

    pkiDir = mkOption {
      type = types.str;
      default = "/var/lib/kubernetes/pki";
      description = "PKI directory for Kubernetes certificates.";
    };

    version = mkOption {
      type = types.str;
      default = config.quad.versions.kubernetes;
      description = "Pinned Kubernetes version for the cluster.";
    };
  };

  config = mkIf (
    (config.services.kubernetes.roles or []) != []
    || (config.services.kubernetes.controlPlane.enable or false)
    || (config.services.kubernetes.worker.enable or false)
  ) {
    environment.etc."kubernetes/common.json".text = builtins.toJSON {
      inherit (cfg) clusterName serviceCIDR podCIDR pkiDir version;
    };
  };
}
