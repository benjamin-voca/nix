{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.services.kubernetes.worker;
  yaml = pkgs.formats.yaml { };
in {
  options.services.kubernetes.worker = {
    enable = mkEnableOption "Kubernetes worker";

    nodeIP = mkOption {
      type = types.str;
      default = "0.0.0.0";
    };

    clusterDNS = mkOption {
      type = types.listOf types.str;
      default = [ "10.96.0.10" ];
    };

    clusterDomain = mkOption {
      type = types.str;
      default = "cluster.local";
    };

    cgroupDriver = mkOption {
      type = types.enum [ "systemd" "cgroupfs" ];
      default = "systemd";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
    };
  };

  config = mkIf cfg.enable {
    environment.etc."kubernetes/kubelet.yaml".source = yaml.generate "kubelet.yaml" {
      "node-ip" = cfg.nodeIP;
      "cluster-dns" = cfg.clusterDNS;
      "cluster-domain" = cfg.clusterDomain;
      "cgroup-driver" = cfg.cgroupDriver;
      "extra-args" = cfg.extraArgs;
    };
  };
}
