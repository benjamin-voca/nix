{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.quadnix.argocd-deploy;
  kubectl = "${pkgs.kubectl}/bin/kubectl";

  helmLib = import ../../lib/helm {
    inherit pkgs;
    nixhelm = inputs.nixhelm;
    nix-kube-generators = inputs.nix-kube-generators;
  };

  argocdChart = import ../../lib/helm/charts/argocd.nix {
    inherit helmLib pkgs lib;
  };

  argocdManifests = argocdChart.argocd;

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
