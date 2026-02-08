{ config, lib, pkgs, ... }:

let
  cfg = config.services.quadnix.argocd-deploy;
  kubectl = "${pkgs.kubectl}/bin/kubectl";

  helmLib = config.flake.helmLib.${pkgs.stdenv.system};

  argocdManifests = helmLib.buildChart {
    name = "argocd";
    chart = helmLib.charts.argoproj.argo-cd;
    namespace = "argocd";
    values = {
      global = {
        domain = "argocd.quadtech.dev";
      };

      configs = {
        cm = {
          "server.insecure" = true;
          url = "https://argocd.quadtech.dev";
        };
        params = {
          "server.insecure" = true;
        };
        secret = {
          argocdServerAdminPassword = "$2a$10$bX.6MmE5x1n.KlTA./3ax.xXzgP5CzLu1CyFyvMnEeh.vN9tDVVLC";
        };
      };

      server = {
        replicas = 1;
        service = {
          type = "ClusterIP";
        };
        ingress = {
          enabled = true;
          ingressClassName = "nginx";
          hostname = "argocd.quadtech.dev";
          tls = false;
          annotations = {
            "nginx.ingress.kubernetes.io/proxy-body-size" = "0";
            "nginx.ingress.kubernetes.io/proxy-read-timeout" = "600";
            "nginx.ingress.kubernetes.io/proxy-send-timeout" = "600";
          };
          pathType = "Prefix";
          paths = [
            {
              path = "/";
              backend = {
                service = {
                  name = "argocd-server";
                  port = {
                    number = 80;
                  };
                };
              };
            }
          ];
        };
      };

      redis = {
        enabled = true;
      };

      redis-ha = {
        enabled = false;
      };

      controller = {
        replicas = 1;
      };

      repoServer = {
        replicas = 1;
      };

      applicationSet = {
        enabled = true;
      };

      notifications = {
        enabled = true;
      };

      global.image.tag = "v2.9.3";
    };
  };

  deploySh = pkgs.writeShellApplication {
    name = "argocd-deploy";
    text = ''
      #!/bin/bash
      set -e
      export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

      echo "Waiting for Kubernetes API..."
      until ${kubectl} cluster-info --request-timeout=10s >/dev/null 2>&1; do
        echo "Waiting for Kubernetes API..."
        sleep 5
      done

      echo "Creating ArgoCD namespace..."
      ${kubectl} create namespace argocd --dry-run=client -o yaml | ${kubectl} apply -f - || true

      echo "Deploying ArgoCD manifests..."
      ${kubectl} apply -f ${argocdManifests} --validate=false

      echo "Waiting for ArgoCD to be ready..."
      ${kubectl} rollout status deployment/argocd-server -n argocd --timeout=300s || true

      echo "ArgoCD deployed successfully!"
      echo "URL: https://argocd.quadtech.dev"
      echo "Admin username: admin"
      echo "Admin password: admin"
    '';
  };

  cleanupSh = pkgs.writeShellApplication {
    name = "argocd-cleanup";
    text = ''
      #!/bin/bash
      set -e
      export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig
      ${kubectl} delete -f ${argocdManifests} --ignore-not-found 2>/dev/null || true
      ${kubectl} delete namespace argocd --ignore-not-found 2>/dev/null || true
    '';
  };
in
{
  options.services.quadnix.argocd-deploy = {
    enable = lib.mkEnableOption "Deploy ArgoCD to Kubernetes via Helm";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      deploySh
      cleanupSh
      pkgs.kubectl
    ];

    systemd.services.argocd-deploy = {
      description = "Deploy ArgoCD to Kubernetes";
      after = [ "network-online.target" "kube-apiserver.service" "ingress-nginx-controller.service" ];
      wants = [ "network-online.target" "kube-apiserver.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${deploySh}/bin/argocd-deploy";
        ExecStop = "${cleanupSh}/bin/argocd-cleanup";
      };
    };
  };
}
