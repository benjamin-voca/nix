# Nix-built Helm Charts Integration

This implementation provides automatic propagation of Nix-built Helm charts to Kubernetes via ArgoCD.

## Architecture

### 1. Nix Flakes for Chart Building
- **Location**: `lib/helm/charts/flake.nix`
- **Charts**: ArgoCD (6.7.2) and Forgejo (4.4.0)
- **Build Process**: Reproducible builds using Nix
- **Output**: Packaged `.tgz` files

### 2. Forgejo as Helm Repository
- **Package Registry**: Forgejo's built-in OCI-compatible package registry
- **Repository URL**: `https://forge.quadtech.dev/chartrepo/quadnix`
- **Authentication**: API tokens for automated publishing

### 3. Automated CI/CD Pipeline
- **Trigger**: Git push to main branch
- **Workflow**: `.forgejo/workflows/build-helm-charts.yaml`
- **Steps**: Build → Validate → Publish → Update index → Notify ArgoCD

### 4. ArgoCD Application Management
- **Application**: `charts-app` in ArgoCD
- **Source**: Git repository with Helm charts
- **Sync Policy**: Automated with self-healing
- **Node Selectors**: Internal apps on backbone nodes

## Node Taints Implementation

### Backbone Nodes
- Taint: `role=backbone:NoSchedule`
- Taint: `infra=true:NoSchedule`
- Purpose: Ensure internal services only run on backbone nodes

### Frontline Nodes
- Taint: `role=frontline:NoSchedule`
- Purpose: Reserve for customer workloads

## Usage

### Build Charts Locally
```bash
nix build .#argocd  # Build ArgoCD chart
nix build .#forgejo   # Build Forgejo chart
```

### Publish Manually (if needed)
```bash
# After building charts
helm package result/*.tgz --destination .

# Upload to Forgejo via API
curl -u "username:$FORGEJO_TOKEN" -X POST "$GITEA_URL/api/packages/quadnix/helm" \
  -F "file=@argocd-6.7.2.tgz"
```

### ArgoCD Configuration
Charts are automatically deployed to K8s via ArgoCD with:
- Node selectors for backbone placement
- Automated sync on new chart versions
- Self-healing capabilities

## Future Expansion

### Adding New Charts
1. Add chart to `flake.nix`
2. Update Forgejo workflow if needed
3. Add to ArgoCD application or create new one

### Scaling to 3:1 Ratio
- Backend services remain on backbone nodes via taints
- Customer workloads scheduled to frontline nodes
- ArgoCD enforces placement policies

## Security
- Forgejo API tokens stored in secrets
- ArgoCD authentication via tokens
- Nix builds are reproducible and auditable