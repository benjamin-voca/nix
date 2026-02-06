{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.services.kubernetes.controlPlane;
  yaml = pkgs.formats.yaml { };
in {
  options.services.kubernetes.controlPlane = {
    enable = mkEnableOption "Kubernetes control-plane";

    version = mkOption {
      type = types.str;
      default = config.services.kubernetes.common.version;
      description = "Pinned Kubernetes version for control-plane nodes.";
    };

    etcd = {
      enable = mkEnableOption "etcd";
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/etcd";
      };
      cluster = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      listenClientUrls = mkOption {
        type = types.listOf types.str;
        default = [ "http://127.0.0.1:2379" ];
      };
      listenPeerUrls = mkOption {
        type = types.listOf types.str;
        default = [ "http://127.0.0.1:2380" ];
      };
      initialClusterState = mkOption {
        type = types.enum [ "new" "existing" ];
        default = "new";
      };
    };

    apiServer = {
      enable = mkEnableOption "API server";
      advertiseAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
      };
      bindPort = mkOption {
        type = types.int;
        default = 6443;
      };
      etcdServers = mkOption {
        type = types.listOf types.str;
        default = [ "http://127.0.0.1:2379" ];
      };
      authorizationModes = mkOption {
        type = types.listOf types.str;
        default = [ "Node" "RBAC" ];
      };
    };

    scheduler = {
      enable = mkEnableOption "Scheduler";
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
      };
      leaderElect = mkOption {
        type = types.bool;
        default = true;
      };
    };

    controllerManager = {
      enable = mkEnableOption "Controller manager";
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
      };
      clusterCIDR = mkOption {
        type = types.str;
        default = config.services.kubernetes.common.podCIDR;
      };
      serviceCIDR = mkOption {
        type = types.str;
        default = config.services.kubernetes.common.serviceCIDR;
      };
      leaderElect = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  config = mkIf cfg.enable {
    environment.etc."kubernetes/control-plane-version".text = cfg.version;

    environment.etc."kubernetes/etcd.conf".source = mkIf cfg.etcd.enable (
      yaml.generate "etcd.conf" {
        name = config.networking.hostName or "control-plane";
        "data-dir" = cfg.etcd.dataDir;
        "listen-client-urls" = cfg.etcd.listenClientUrls;
        "listen-peer-urls" = cfg.etcd.listenPeerUrls;
        "initial-cluster" = cfg.etcd.cluster;
        "initial-cluster-state" = cfg.etcd.initialClusterState;
      }
    );

    environment.etc."kubernetes/api-server.yaml".source = mkIf cfg.apiServer.enable (
      yaml.generate "api-server.yaml" {
        "advertise-address" = cfg.apiServer.advertiseAddress;
        "bind-port" = cfg.apiServer.bindPort;
        "etcd-servers" = cfg.apiServer.etcdServers;
        "authorization-mode" = cfg.apiServer.authorizationModes;
      }
    );

    environment.etc."kubernetes/scheduler.yaml".source = mkIf cfg.scheduler.enable (
      yaml.generate "scheduler.yaml" {
        "bind-address" = cfg.scheduler.bindAddress;
        "leader-elect" = cfg.scheduler.leaderElect;
      }
    );

    environment.etc."kubernetes/controller-manager.yaml".source = mkIf cfg.controllerManager.enable (
      yaml.generate "controller-manager.yaml" {
        "bind-address" = cfg.controllerManager.bindAddress;
        "cluster-cidr" = cfg.controllerManager.clusterCIDR;
        "service-cluster-ip-range" = cfg.controllerManager.serviceCIDR;
        "leader-elect" = cfg.controllerManager.leaderElect;
      }
    );
  };
}
