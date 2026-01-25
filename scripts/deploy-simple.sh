#!/usr/bin/env bash
# Simple deployment script for single-instance Kubernetes with Cloudflare Tunnel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found. Please ensure Kubernetes is running."
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster. Is it running?"
    exit 1
fi

info "Connected to Kubernetes cluster"

# Deploy services
deploy_service() {
    local service=$1
    local chart=$2
    local namespace=$3
    
    info "Deploying $service to namespace $namespace..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    # Build the Helm chart using Nix
    info "Building Helm chart for $service..."
    if ! nix build "$PROJECT_ROOT#helmCharts.x86_64-linux.$chart"; then
        error "Failed to build Helm chart for $service"
        return 1
    fi
    
    # Apply the chart
    info "Applying Helm chart for $service..."
    if kubectl apply -f result/; then
        info "✓ $service deployed successfully"
    else
        error "Failed to deploy $service"
        return 1
    fi
}

# Expose services via NodePort for Cloudflare Tunnel
expose_service() {
    local service=$1
    local namespace=$2
    local port=$3
    local nodeport=$4
    
    info "Exposing $service on NodePort $nodeport..."
    
    kubectl -n "$namespace" patch svc "$service" -p "{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"port\":$port,\"nodePort\":$nodeport}]}}" || true
}

# Main deployment menu
main() {
    echo "================================================"
    echo "  QuadNix Single-Instance K8s Deployment"
    echo "================================================"
    echo ""
    echo "This script deploys services to Kubernetes with"
    echo "Cloudflare Tunnel integration."
    echo ""
    echo "Available services:"
    echo "  1) Gitea (Git service)"
    echo "  2) ClickHouse (Analytics database)"
    echo "  3) Grafana (Observability)"
    echo "  4) All services"
    echo "  5) Show service status"
    echo "  6) Port-forward services (for Cloudflare Tunnel)"
    echo "  0) Exit"
    echo ""
    read -p "Select option: " choice
    
    case $choice in
        1)
            deploy_service "Gitea" "gitea-simple" "gitea"
            expose_service "gitea-http" "gitea" 3000 30080
            ;;
        2)
            deploy_service "ClickHouse" "clickhouse-simple" "clickhouse"
            expose_service "clickhouse" "clickhouse" 8123 30081
            ;;
        3)
            deploy_service "Grafana" "grafana-simple" "grafana"
            expose_service "grafana" "grafana" 80 30082
            ;;
        4)
            deploy_service "Gitea" "gitea-simple" "gitea"
            deploy_service "ClickHouse" "clickhouse-simple" "clickhouse"
            deploy_service "Grafana" "grafana-simple" "grafana"
            
            expose_service "gitea-http" "gitea" 3000 30080
            expose_service "clickhouse" "clickhouse" 8123 30081
            expose_service "grafana" "grafana" 80 30082
            
            info "All services deployed!"
            ;;
        5)
            info "Service status:"
            echo ""
            kubectl get pods -n gitea
            echo ""
            kubectl get pods -n clickhouse
            echo ""
            kubectl get pods -n grafana
            ;;
        6)
            info "Setting up port-forwards for Cloudflare Tunnel..."
            echo "Run these commands in separate terminals:"
            echo ""
            echo "  kubectl port-forward -n gitea svc/gitea-http 30080:3000"
            echo "  kubectl port-forward -n clickhouse svc/clickhouse 30081:8123"
            echo "  kubectl port-forward -n grafana svc/grafana 30082:80"
            echo ""
            ;;
        0)
            info "Exiting..."
            exit 0
            ;;
        *)
            error "Invalid option"
            exit 1
            ;;
    esac
}

main
