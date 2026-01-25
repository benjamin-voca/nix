#!/usr/bin/env bash
# Script to update and test the nixhelm integration

set -euo pipefail

echo "==> Updating flake inputs..."
nix flake update nixhelm nix-kube-generators

echo ""
echo "==> Testing helm library outputs..."
nix eval .#helmLib.x86_64-linux --apply 'lib: builtins.attrNames lib'

echo ""
echo "==> Listing available chart repositories..."
nix eval .#chartsMetadata --apply 'md: builtins.attrNames md' 2>/dev/null || echo "Run 'nix flake update' first to fetch chart metadata"

echo ""
echo "==> Testing pre-configured charts..."
nix eval .#helmCharts.x86_64-linux --apply 'charts: builtins.attrNames charts.all'

echo ""
echo "==> Example: Building ArgoCD chart..."
echo "Run: nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd"

echo ""
echo "==> Example: Accessing Prometheus chart..."
echo "Run: nix build .#chartsDerivations.x86_64-linux.prometheus-community.kube-prometheus-stack"

echo ""
echo "✓ Nixhelm integration test complete!"
