#!/usr/bin/env bash
# QuadNix Deployment Script
# Automates the deployment of backbone and frontline infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

wait_for_pods() {
    local namespace=$1
    local timeout=${2:-300}
    
    info "Waiting for pods in namespace $namespace to be ready..."
    kubectl wait --for=condition=ready pod \
        --all \
        --namespace="$namespace" \
        --timeout="${timeout}s" || true
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    command -v nix >/dev/null 2>&1 || error "nix is not installed"
    command -v kubectl >/dev/null 2>&1 || error "kubectl is not installed"
    command -v helm >/dev/null 2>&1 || error "helm is not installed"
    
    success "All prerequisites met"
}

# Deploy backbone nodes (NixOS configuration)
deploy_backbone() {
    info "Deploying backbone nodes..."
    
    for node in backbone-01 backbone-02; do
        info "Building configuration for $node..."
        nix build ".#nixosConfigurations.$node.config.system.build.toplevel" \
            || error "Failed to build $node configuration"
    done
    
    warning "Backbone NixOS configurations built successfully"
    warning "To deploy, run on each backbone node:"
    echo "  sudo nixos-rebuild switch --flake .#backbone-01"
    echo "  sudo nixos-rebuild switch --flake .#backbone-02"
}

# Deploy frontline nodes (NixOS configuration)
deploy_frontline() {
    info "Deploying frontline nodes..."
    
    for node in frontline-01 frontline-02; do
        info "Building configuration for $node..."
        nix build ".#nixosConfigurations.$node.config.system.build.toplevel" \
            || error "Failed to build $node configuration"
    done
    
    warning "Frontline NixOS configurations built successfully"
    warning "To deploy, run on each frontline node:"
    echo "  sudo nixos-rebuild switch --flake .#frontline-01"
    echo "  sudo nixos-rebuild switch --flake .#frontline-02"
}

# Deploy Kubernetes infrastructure
deploy_k8s_infrastructure() {
    info "Deploying Kubernetes infrastructure..."
    
    # Create namespaces
    info "Creating namespaces..."
    kubectl apply -f manifests/backbone/namespaces.yaml
    
    # Deploy ingress-nginx
    info "Deploying ingress-nginx..."
    nix build ".#helmCharts.x86_64-linux.all.ingress-nginx"
    helm upgrade --install ingress-nginx ./result/*.tgz \
        -n ingress-nginx \
        --create-namespace \
        --wait
    wait_for_pods ingress-nginx 120
    
    # Deploy cert-manager
    info "Deploying cert-manager..."
    nix build ".#helmCharts.x86_64-linux.all.cert-manager"
    helm upgrade --install cert-manager ./result/*.tgz \
        -n cert-manager \
        --create-namespace \
        --wait
    wait_for_pods cert-manager 120
    
    success "Kubernetes infrastructure deployed"
}

# Deploy monitoring stack
deploy_monitoring() {
    info "Deploying monitoring stack..."
    
    # Deploy Prometheus
    info "Deploying Prometheus..."
    nix build ".#helmCharts.x86_64-linux.all.prometheus"
    helm upgrade --install prometheus ./result/*.tgz \
        -n monitoring \
        --create-namespace \
        --wait \
        --timeout 10m
    
    # Deploy Grafana
    info "Deploying Grafana..."
    nix build ".#helmCharts.x86_64-linux.all.grafana"
    helm upgrade --install grafana ./result/*.tgz \
        -n grafana \
        --create-namespace \
        --wait \
        --timeout 10m
    
    # Deploy Loki
    info "Deploying Loki..."
    nix build ".#helmCharts.x86_64-linux.all.loki"
    helm upgrade --install loki ./result/*.tgz \
        -n loki \
        --create-namespace \
        --wait \
        --timeout 10m
    
    success "Monitoring stack deployed"
}

# Deploy backbone services
deploy_backbone_services() {
    info "Deploying backbone services..."
    
    # Deploy Gitea
    info "Deploying Gitea..."
    nix build ".#helmCharts.x86_64-linux.all.gitea"
    helm upgrade --install gitea ./result/*.tgz \
        -n gitea \
        --create-namespace \
        --wait \
        --timeout 10m
    
    # Deploy ClickHouse operator
    info "Deploying ClickHouse operator..."
    nix build ".#helmCharts.x86_64-linux.all.clickhouse-operator"
    helm upgrade --install clickhouse-operator ./result/*.tgz \
        -n clickhouse-operator \
        --create-namespace \
        --wait
    
    # Deploy ClickHouse
    info "Deploying ClickHouse..."
    nix build ".#helmCharts.x86_64-linux.all.clickhouse"
    helm upgrade --install clickhouse ./result/*.tgz \
        -n clickhouse \
        --create-namespace \
        --wait \
        --timeout 15m
    
    success "Backbone services deployed"
}

# Show deployment status
show_status() {
    info "Deployment Status:"
    echo ""
    
    echo "=== Nodes ==="
    kubectl get nodes -o wide
    echo ""
    
    echo "=== Namespaces ==="
    kubectl get namespaces
    echo ""
    
    echo "=== Pods (All Namespaces) ==="
    kubectl get pods --all-namespaces
    echo ""
    
    echo "=== Services ==="
    kubectl get svc --all-namespaces
    echo ""
    
    echo "=== Ingresses ==="
    kubectl get ingress --all-namespaces
    echo ""
    
    info "Service URLs:"
    echo "  Gitea:      https://git.quadtech.dev"
    echo "  Grafana:    https://grafana.quadtech.dev"
    echo "  ClickHouse: https://clickhouse.quadtech.dev"
    echo "  Prometheus: https://prometheus.quadtech.dev"
    echo ""
    
    warning "Default passwords are set to 'changeme' - CHANGE THEM IMMEDIATELY!"
}

# Main menu
main() {
    echo ""
    echo "========================================="
    echo "  QuadNix Deployment Script"
    echo "========================================="
    echo ""
    
    check_prerequisites
    
    PS3="Select deployment option: "
    options=(
        "Deploy All (Recommended)"
        "Deploy Backbone NixOS Configs"
        "Deploy Frontline NixOS Configs"
        "Deploy K8s Infrastructure"
        "Deploy Monitoring Stack"
        "Deploy Backbone Services"
        "Show Status"
        "Quit"
    )
    
    select opt in "${options[@]}"; do
        case $opt in
            "Deploy All (Recommended)")
                deploy_backbone
                deploy_frontline
                warning "Please deploy the NixOS configurations on each node, then run this script again"
                warning "After nodes are deployed, select 'Deploy K8s Infrastructure' to continue"
                break
                ;;
            "Deploy Backbone NixOS Configs")
                deploy_backbone
                break
                ;;
            "Deploy Frontline NixOS Configs")
                deploy_frontline
                break
                ;;
            "Deploy K8s Infrastructure")
                deploy_k8s_infrastructure
                deploy_monitoring
                deploy_backbone_services
                show_status
                break
                ;;
            "Deploy Monitoring Stack")
                deploy_monitoring
                break
                ;;
            "Deploy Backbone Services")
                deploy_backbone_services
                break
                ;;
            "Show Status")
                show_status
                break
                ;;
            "Quit")
                info "Exiting..."
                exit 0
                ;;
            *)
                error "Invalid option $REPLY"
                ;;
        esac
    done
}

main "$@"
