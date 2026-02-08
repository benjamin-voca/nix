{ config, lib, pkgs, ... }:

let
  cfg = config.services.quadnix.argocd-deploy;
  kubectl = "${pkgs.kubectl}/bin/kubectl";
  
  deployScript = pkgs.writeShellApplication {
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
      
      echo "Creating ArgoCD prerequisites..."
      
      # Create namespace
      ${kubectl} create namespace argocd --dry-run=client -o yaml | ${kubectl} apply -f - || true
      
      # Generate and create redis secret
      REDIS_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 32)
      ${kubectl} create secret generic argocd-redis \
        --from-literal=auth="$REDIS_PASSWORD" \
        --namespace=argocd \
        --dry-run=client -o yaml | ${kubectl} apply -f -
      
      echo "Deploying ArgoCD..."
      
      # Add argo helm repo
      ${pkgs.kubernetes-helm}/bin/helm repo add argo https://argoproj.github.io/argo-helm --force-update 2>/dev/null || true
      ${pkgs.kubernetes-helm}/bin/helm repo update
      
      # Uninstall any existing ArgoCD first (in case of partial install)
      echo "Cleaning up any existing ArgoCD installation..."
      ${pkgs.kubernetes-helm}/bin/helm uninstall argocd -n argocd --ignore-not-found 2>/dev/null || true
      
      # Wait for cleanup to complete
      sleep 5
      
      # Deploy using helm with values
      ${pkgs.kubernetes-helm}/bin/helm upgrade --install argocd argo/argo-cd \
        --namespace argocd \
        --version 5.51.6 \
        --set global.domain=argocd.quadtech.dev \
        --set configs.cm.server.insecure=true \
        --set configs.params.server.insecure=true \
        --set configs.secret.argocdServerAdminPassword="\$2a\$10\$bX.6MmE5x1n.KlTA./3ax.xXzgP5CzLu1CyFyvMnEeh.vN9tDVVLC" \
        --set server.replicas=1 \
        --set server.service.type=ClusterIP \
        --set server.ingress.enabled=true \
        --set server.ingress.ingressClassName=nginx \
        --set server.ingress.hostname=argocd.quadtech.dev \
        --set server.ingress.tls=false \
        --set redis.enabled=true \
        --set redis-ha.enabled=false \
        --set controller.replicas=1 \
        --set repoServer.replicas=1 \
        --set applicationSet.enabled=true \
        --set notifications.enabled=true \
        --set global.image.tag=v2.9.3 \
        --wait --timeout 5m || true
      
      # Fix repo-server init container command (replace --update=none with -f)
      echo "Fixing repo-server init container..."
      ${kubectl} patch deployment -n argocd argocd-repo-server --type='json' -p='[
        {"op": "replace", "path": "/spec/template/spec/initContainers/0/command", "value": ["/bin/cp", "-f", "/usr/local/bin/argocd", "/var/run/argocd/argocd-cmp-server"]}
      ]' 2>/dev/null || true
      
      echo "ArgoCD deployed successfully!"
      echo "Admin username: admin"
      echo "Admin password: admin"
    '';
  };

  cleanupScript = pkgs.writeShellApplication {
    name = "argocd-cleanup";
    text = ''
      #!/bin/bash
      set -e
      export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig
      ${pkgs.kubernetes-helm}/bin/helm uninstall argocd -n argocd --ignore-not-found 2>/dev/null || true
    '';
  };
in
{
  options.services.quadnix.argocd-deploy = {
    enable = lib.mkEnableOption "Deploy ArgoCD to Kubernetes";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      deployScript
      cleanupScript
      pkgs.kubectl
      pkgs.kubernetes-helm
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
        ExecStart = "${deployScript}/bin/argocd-deploy";
        ExecStop = "${cleanupScript}/bin/argocd-cleanup";
      };
    };
  };
}
