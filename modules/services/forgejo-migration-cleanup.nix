{ config, lib, pkgs, ... }:

let
  cfg = config.services.quadnix.forgejo-migration-cleanup;
in
{
  options.services.quadnix.forgejo-migration-cleanup = {
    enable = lib.mkEnableOption "Clean up legacy Gitea migration leftovers";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "forgejo-migration-cleanup";
        text = ''
          #!/bin/bash
          set -euo pipefail

          export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig
          kubectl="${pkgs.kubectl}/bin/kubectl"

          echo "Waiting for Kubernetes API..."
          until $kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; do
            echo "Waiting for Kubernetes API..."
            sleep 5
          done

          if $kubectl get namespace gitea >/dev/null 2>&1; then
            echo "Deleting legacy gitea namespace..."
            $kubectl delete namespace gitea --ignore-not-found --wait=false
          else
            echo "Legacy gitea namespace already absent"
          fi

          if $kubectl -n forgejo get pvc forgejo-shared-storage-ceph >/dev/null 2>&1; then
            echo "Deleting stale Forgejo PVC forgejo-shared-storage-ceph..."
            $kubectl -n forgejo delete pvc forgejo-shared-storage-ceph --ignore-not-found
          else
            echo "Stale Forgejo PVC already absent"
          fi

          echo "Forgejo migration cleanup complete."
        '';
      })
      pkgs.kubectl
    ];

    systemd.services.forgejo-migration-cleanup = {
      description = "Clean up legacy Gitea migration leftovers";
      after = [ "network-online.target" "kube-apiserver.service" ];
      wants = [ "network-online.target" "kube-apiserver.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/sw/bin/forgejo-migration-cleanup";
      };
    };
  };
}
