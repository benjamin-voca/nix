#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

echo "Getting Gitea passwords..."
export GITEA_DB_PASSWORD=$(SOPS_AGE_KEY_FILE=/etc/sops/age/keys.txt sops -d /etc/nixos/secrets/backbone-01.yaml | rg -o "gitea-db-password: (.*)$" -r '$1')
export GITEA_ADMIN_PASSWORD=$(SOPS_AGE_KEY_FILE=/etc/sops/age/keys.txt sops -d /etc/nixos/secrets/backbone-01.yaml | rg -o "gitea-admin-password: (.*)$" -r '$1')

echo "Building Gitea Helm chart..."
cd /etc/nixos
rm -f result
nix build .#helmCharts.x86_64-linux.all.gitea

echo "Deploying Gitea..."
envsubst '${GITEA_DB_PASSWORD} ${GITEA_ADMIN_PASSWORD}' < ./result | kubectl apply -f -

echo "Removing broken init containers..."
kubectl patch deployment gitea -n gitea --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/initContainers"}]' 2>/dev/null || true

echo "Restarting Gitea..."
kubectl rollout restart -n gitea deployment/gitea

echo "Cleaning up..."
kubectl delete pod -n gitea gitea-test-connection 2>/dev/null || true

echo "Done!"
