#!/usr/bin/env bash
# Quick fix to enable services on backbone-01
# 
# This script helps you choose and enable the right configuration

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "=========================================="
echo "  Backbone Services Configuration"
echo "=========================================="
echo ""

info "Current backbone.nix status:"
echo ""

if grep -q "# ../profiles/kubernetes/control-plane.nix" roles/backbone.nix 2>/dev/null; then
    warning "Kubernetes control plane is DISABLED (commented out)"
else
    success "Kubernetes control plane is ENABLED"
fi

if grep -q "../services/gitea.nix" roles/backbone.nix 2>/dev/null; then
    success "Gitea NixOS service is ENABLED"
else
    warning "Gitea NixOS service is DISABLED"
fi

if grep -q "# ../services/clickhouse.nix" roles/backbone.nix 2>/dev/null; then
    warning "ClickHouse NixOS service is DISABLED (commented out)"
elif grep -q "../services/clickhouse.nix" roles/backbone.nix 2>/dev/null; then
    success "ClickHouse NixOS service is ENABLED"
else
    warning "ClickHouse NixOS service is NOT CONFIGURED"
fi

echo ""
echo "Choose deployment option:"
echo ""
echo "1) NixOS Services (Simple)"
echo "   - Services run directly on the host as systemd services"
echo "   - Good for: Single server, testing, simpler setup"
echo "   - Services: Gitea, ClickHouse on backbone-01"
echo ""
echo "2) Kubernetes Services (Production)"
echo "   - Services run on Kubernetes cluster using Helm charts"
echo "   - Good for: Multi-node, HA, production, client separation"
echo "   - Services: Gitea, ClickHouse, Grafana, Prometheus, etc."
echo ""
echo "3) Show difference between options"
echo ""
echo "4) Exit (no changes)"
echo ""

read -p "Enter choice [1-4]: " choice

case $choice in
    1)
        info "Configuring for NixOS Services..."
        
        # Backup current config
        cp roles/backbone.nix roles/backbone.nix.backup.$(date +%s)
        success "Backed up current config"
        
        # Create new config
        cat > roles/backbone.nix <<'EOF'
# Backbone Role - NixOS Services
# Services run directly on the host as systemd services

{ config, pkgs, ... }:

{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../services/gitea.nix
    ../services/clickhouse.nix
  ];

  networking.firewall.allowedTCPPorts = [
    22        # SSH
    80        # HTTP
    443       # HTTPS
    2222      # Gitea SSH
    3000      # Gitea HTTP (if not on 443)
    8123      # ClickHouse HTTP
    9000      # ClickHouse TCP
  ];

  environment.systemPackages = with pkgs; [
    kubectl  # For future K8s if needed
    git
    htop
  ];
}
EOF
        
        success "Updated roles/backbone.nix for NixOS services"
        echo ""
        warning "Next steps:"
        echo "  1. Deploy to backbone-01:"
        echo "     sudo nixos-rebuild switch --flake .#backbone-01"
        echo ""
        echo "  2. Verify services:"
        echo "     systemctl status gitea"
        echo "     systemctl status clickhouse"
        echo ""
        echo "  3. Access services:"
        echo "     Gitea: http://192.168.1.10:3000 or https://git.quadtech.dev"
        echo "     ClickHouse: http://192.168.1.10:8123"
        ;;
    
    2)
        info "Configuring for Kubernetes Services..."
        
        # Backup current config
        cp roles/backbone.nix roles/backbone.nix.backup.$(date +%s)
        success "Backed up current config"
        
        # Use the updated backbone config
        if [ -f roles/backbone-updated.nix ]; then
            cp roles/backbone-updated.nix roles/backbone.nix
            success "Updated roles/backbone.nix for Kubernetes services"
        else
            # Create it from scratch
            cat > roles/backbone.nix <<'EOF'
# Backbone Role - Kubernetes Services
# Services run on Kubernetes using Helm charts

{ config, pkgs, ... }:

{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/helm.nix
  ];

  # Enable Kubernetes control plane
  services.kubernetes = {
    roles = [ "master" ];
    controlPlane = {
      enable = true;
      etcd.enable = true;
      apiServer.enable = true;
      scheduler.enable = true;
      controllerManager.enable = true;
    };
  };

  networking.firewall.allowedTCPPorts = [
    22       # SSH
    443      # HTTPS
    6443     # Kubernetes API
    2379     # etcd client
    2380     # etcd peer
    10250    # kubelet
    10251    # kube-scheduler
    10252    # kube-controller-manager
  ];

  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s
  ];
}
EOF
            success "Updated roles/backbone.nix for Kubernetes services"
        fi
        
        echo ""
        warning "Next steps:"
        echo "  1. Deploy NixOS with Kubernetes:"
        echo "     sudo nixos-rebuild switch --flake .#backbone-01"
        echo ""
        echo "  2. Wait for Kubernetes to start (2-3 minutes):"
        echo "     kubectl get nodes"
        echo ""
        echo "  3. Deploy services using Helm charts:"
        echo "     ./scripts/deploy.sh"
        echo ""
        echo "  4. Or deploy manually:"
        echo "     See docs/DEPLOYMENT.md for full instructions"
        ;;
    
    3)
        info "Showing differences between options..."
        echo ""
        echo "=== OPTION 1: NixOS Services ==="
        echo "• Gitea runs as systemd service"
        echo "• ClickHouse runs as systemd service"
        echo "• Access: Direct to ports (3000, 8123, etc.)"
        echo "• Management: systemctl, journalctl"
        echo "• Single server only"
        echo ""
        echo "=== OPTION 2: Kubernetes Services ==="
        echo "• All services run in Kubernetes pods"
        echo "• Deployed via Helm charts (from lib/helm/charts/)"
        echo "• Access: Via ingress (git.quadtech.dev, etc.)"
        echo "• Management: kubectl, helm"
        echo "• Multi-node, high availability"
        echo "• Includes: Gitea, ClickHouse, Grafana, Prometheus, Loki"
        echo ""
        echo "See docs/BACKBONE-SERVICES.md for detailed comparison"
        ;;
    
    4)
        info "Exiting without changes"
        exit 0
        ;;
    
    *)
        error "Invalid choice"
        ;;
esac

echo ""
success "Configuration complete!"
