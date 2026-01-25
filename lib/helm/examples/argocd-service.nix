# Example: Deploying ArgoCD using nixhelm

{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.quadnix.argocd;
  
  # Get the helm library from the flake
  helmLib = inputs.self.helmLib.${pkgs.system};
  
  # Build the ArgoCD chart with custom values
  argocdChart = helmLib.buildChart {
    name = "argocd";
    chart = helmLib.charts.argoproj.argo-cd;
    namespace = cfg.namespace;
    values = {
      server = {
        replicas = cfg.replicas;
        service.type = "ClusterIP";
        ingress = mkIf cfg.ingress.enable {
          enabled = true;
          ingressClassName = cfg.ingress.className;
          hosts = cfg.ingress.hosts;
          tls = mkIf (cfg.ingress.tlsSecretName != null) [{
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
    enable = mkEnableOption "ArgoCD GitOps platform";

    namespace = mkOption {
      type = types.str;
      default = "argocd";
      description = "Kubernetes namespace for ArgoCD";
    };

    version = mkOption {
      type = types.str;
      default = "v2.9.3";
      description = "ArgoCD version to deploy";
    };

    replicas = mkOption {
      type = types.int;
      default = 2;
      description = "Number of ArgoCD server replicas";
    };

    highAvailability = mkOption {
      type = types.bool;
      default = true;
      description = "Enable high availability mode with Redis HA";
    };

    ingress = {
      enable = mkEnableOption "Ingress for ArgoCD";

      className = mkOption {
        type = types.str;
        default = "nginx";
        description = "Ingress class name";
      };

      hosts = mkOption {
        type = types.listOf types.str;
        default = [ "argocd.example.com" ];
        description = "Hostnames for ArgoCD ingress";
      };

      tlsSecretName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "TLS secret name for HTTPS";
      };
    };
  };

  config = mkIf cfg.enable {
    # Add ArgoCD chart to system packages
    # In a real deployment, you'd apply this to your Kubernetes cluster
    environment.systemPackages = [ argocdChart ];

    # Optionally add kubectl and helm CLI tools
    environment.systemPackages = with pkgs; [
      kubectl
      kubernetes-helm
    ];
  };
}
