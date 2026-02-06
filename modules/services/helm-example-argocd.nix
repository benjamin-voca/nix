{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.quadnix.argocd;
  helmLib = inputs.self.helmLib.${pkgs.system};
  argocdChart = helmLib.buildChart {
    name = "argocd";
    chart = helmLib.charts.argoproj.argo-cd;
    namespace = cfg.namespace;
    values = {
      server = {
        replicas = cfg.replicas;
        service.type = "ClusterIP";
        ingress = lib.mkIf cfg.ingress.enable {
          enabled = true;
          ingressClassName = cfg.ingress.className;
          hosts = cfg.ingress.hosts;
          tls = lib.mkIf (cfg.ingress.tlsSecretName != null) [{
            secretName = cfg.ingress.tlsSecretName;
            hosts = cfg.ingress.hosts;
          }];
        };
      };

      redis-ha.enabled = cfg.highAvailability;
      controller.replicas = if cfg.highAvailability then 1 else 1;
      repoServer.replicas = if cfg.highAvailability then cfg.replicas else 1;

      global.image.tag = cfg.version;
    };
  };
in {
  options.services.quadnix.argocd = {
    enable = lib.mkEnableOption "ArgoCD GitOps platform";

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "argocd";
      description = "Kubernetes namespace for ArgoCD";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "v2.9.3";
      description = "ArgoCD version to deploy";
    };

    replicas = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Number of ArgoCD server replicas";
    };

    highAvailability = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable high availability mode with Redis HA";
    };

    ingress = {
      enable = lib.mkEnableOption "Ingress for ArgoCD";

      className = lib.mkOption {
        type = lib.types.str;
        default = "nginx";
        description = "Ingress class name";
      };

      hosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "argocd.example.com" ];
        description = "Hostnames for ArgoCD ingress";
      };

      tlsSecretName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "TLS secret name for HTTPS";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      argocdChart
      pkgs.kubectl
      pkgs.kubernetes-helm
    ];
  };
}
