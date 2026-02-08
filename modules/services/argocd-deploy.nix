{ config, lib, pkgs, argocdChart, ... }:

let
  cfg = config.services.quadnix.argocd-deploy;
  system = pkgs.stdenv.system;
  chart = argocdChart.${system};
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
          $kubectl delete -f ${chart} --ignore-not-found 2>/dev/null || true

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
          $kubectl apply -f ${chart} --validate=false

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
          $kubectl delete -f ${chart} --ignore-not-found 2>/dev/null || true
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
