#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

echo "Getting Forgejo secrets..."
export FORGEJO_DB_PASSWORD=$(SOPS_AGE_KEY_FILE=/etc/sops/age/keys.txt sops -d /etc/nixos/secrets/backbone-01.yaml | rg -o "forgejo-db-password: (.*)$" -r '$1')
export FORGEJO_ADMIN_PASSWORD=$(SOPS_AGE_KEY_FILE=/etc/sops/age/keys.txt sops -d /etc/nixos/secrets/backbone-01.yaml | rg -o "forgejo-admin-password: (.*)$" -r '$1')

echo "Building Forgejo Helm chart..."
cd /etc/nixos
rm -f result
nix build .#helmCharts.x86_64-linux.all.forgejo

echo "Deploying Forgejo..."
kubectl apply -f ./result

echo "Ensuring Forgejo admin secret exists..."
kubectl create secret generic forgejo-admin \
  --namespace=forgejo \
  --from-literal=username=forgejo_admin \
  --from-literal=password="$FORGEJO_ADMIN_PASSWORD" \
  --from-literal=email=admin@quadtech.dev \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Waiting for Forgejo deployment rollout..."
kubectl rollout status -n forgejo deployment/forgejo --timeout=300s

echo "Done!"
