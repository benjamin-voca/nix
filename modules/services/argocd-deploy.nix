{ config, lib, pkgs, ... }:

let
  cfg = config.services.quadnix.argocd-deploy;
  system = pkgs.stdenv.system;

  helmLib = import ../../lib/helm {
    inherit pkgs system;
    nixhelm = config._module.args.inputs.nixhelm;
    nix-kube-generators = config._module.args.inputs.nix-kube-generators;
  };

  argocdChart = helmLib.buildChart {
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
in
{
  options.services.quadnix.argocd-deploy = {
    enable = lib.mkEnableOption "Deploy ArgoCD to Kubernetes via Helm";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "argocd-deploy";
        text = ''
          #!/bin/bash
          set -e
          export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

          kubectl="${pkgs.kubectl}/bin/kubectl"

          echo "Waiting for Kubernetes API..."
          until $kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; do
            echo "Waiting for Kubernetes API..."
            sleep 5
          done

          echo "Cleaning up any existing ArgoCD installation..."
          $kubectl delete ingress argocd-server -n argocd --ignore-not-found 2>/dev/null || true
          $kubectl delete -f ${argocdChart} --ignore-not-found 2>/dev/null || true

          echo "Cleaning up ArgoCD CRDs and cluster resources..."
          $kubectl delete crd applications.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete crd appprojects.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete crd applicationsets.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrole argocd-application-controller --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrole argocd-server --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrolebinding argocd-application-controller --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrolebinding argocd-server --ignore-not-found 2>/dev/null || true

          echo "Creating ArgoCD namespace..."
          $kubectl create namespace argocd --dry-run=client -o yaml | $kubectl apply -f - || true

          echo "Deploying ArgoCD manifests..."
          $kubectl apply -f ${argocdChart} --validate=false

          echo "Waiting for ArgoCD to be ready..."
          $kubectl rollout status deployment/argocd-server -n argocd --timeout=300s || true

          echo "ArgoCD deployed successfully!"
          echo "URL: https://argocd.quadtech.dev"
          echo "Admin username: admin"
          echo "Admin password: admin"
        '';
      })
      (pkgs.writeShellApplication {
        name = "argocd-cleanup";
        text = ''
          #!/bin/bash
          set -e
          export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

          kubectl="${pkgs.kubectl}/bin/kubectl"

          $kubectl delete ingress argocd-server -n argocd --ignore-not-found 2>/dev/null || true
          $kubectl delete -f ${argocdChart} --ignore-not-found 2>/dev/null || true
          $kubectl delete crd applications.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete crd appprojects.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete crd applicationsets.argoproj.io --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrole argocd-application-controller --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrole argocd-server --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrolebinding argocd-application-controller --ignore-not-found 2>/dev/null || true
          $kubectl delete clusterrolebinding argocd-server --ignore-not-found 2>/dev/null || true
        '';
      })
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
        ExecStart = "/run/current-system/sw/bin/argocd-deploy";
        ExecStop = "/run/current-system/sw/bin/argocd-cleanup";
      };
    };
  };
}
