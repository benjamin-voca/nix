# CI/CD Pipeline

## Overview

The CI/CD pipeline runs on **Forgejo Actions** and is defined in `.forgejo/workflows/ci.yaml`.

### Pipeline Stages

```
Push / PR to main
│
├── test                  (all branches)
│   ├── nix fmt --check
│   ├── nix flake check   (unit tests, kubeconform, conftest policy)
│   └── Build all 4 NixOS configs
│
├── validate-manifests    (all branches)
│   ├── Build bootstrap manifests
│   ├── kubeconform validation
│   └── Diff against docs/reference-bootstrap.yaml
│
├── chart-validation      (all branches)
│   ├── Build Helm charts
│   ├── Validate chart archives
│   ├── Enforce conventional commit scopes
│   └── Generate changelog preview
│
├── publish-helm          (main only, after all checks)
│   ├── Build Helm charts
│   └── Publish to Forgejo Helm registry
│
└── deploy                (main only, after all checks)
    ├── Build bootstrap manifests
    ├── kubectl apply (server-side apply)
    ├── Trigger ArgoCD sync for all Applications
    └── deploy-rs to backbone-01
```

## Required Secrets

Configure these in **Forgejo → Repo → Settings → Actions → Secrets**:

| Secret | Description |
|--------|-------------|
| `KUBECONFIG_BASE64` | Base64-encoded kubeconfig for the Kubernetes cluster |
| `ARGOCD_SERVER` | ArgoCD server URL (e.g. `http://argocd-server.argocd:80`) |
| `ARGOCD_API_TOKEN` | ArgoCD API token for triggering syncs |
| `FORGEJO_TOKEN` | Forgejo API token for publishing Helm charts |

### Creating the secrets

#### KUBECONFIG_BASE64

```bash
# From backbone-01:
base64 -w0 /etc/kubernetes/cluster-admin.kubeconfig
```

**For CI runners inside the cluster**, use the internal service URL:
```bash
# Edit the kubeconfig to use https://kubernetes.default.svc before encoding
sed 's/server: .*/server: https:\/\/kubernetes.default.svc/' \
  /etc/kubernetes/cluster-admin.kubeconfig | base64 -w0
```

**For external runners**, use the external API endpoint:
```bash
base64 -w0 /etc/kubernetes/cluster-admin.kubeconfig
```

#### ARGOCD_SERVER

- Inside cluster: `http://argocd-server.argocd:80`
- External: `https://argocd.quadtech.dev`

#### ARGOCD_API_TOKEN

```bash
# Login to ArgoCD
argocd login argocd.quadtech.dev --username admin --password <password>

# Create a project token (or use admin token for CI)
argocd account generate-token --account admin
```

Alternatively, create a dedicated CI service account in ArgoCD.

## Testing Kubernetes Manifest Changes Before Deploy

The `validate-manifests` job builds the bootstrap output and performs these checks **before** anything reaches the cluster:

1. **`nix flake check`** includes `kubeconform` — validates every YAML document against the Kubernetes 1.29 OpenAPI schema
2. **`nix flake check`** includes `conftest` — runs Rego policy checks (all ArgoCD Applications must have `automated.prune` and `automated.selfHeal`)
3. **Manifest diff** — compares the built `bootstrap.yaml` against `docs/reference-bootstrap.yaml`

### Updating the reference bootstrap

When you intentionally change bootstrap manifests:

```bash
./scripts/update-reference-bootstrap.sh
git add docs/reference-bootstrap.yaml
git commit -m "chore(docs): update reference bootstrap"
```

### What the diff catches

- Accidental removal of a namespace, deployment, or service
- Unintended changes to resource specs (e.g., replica counts, image tags)
- Reordering or formatting changes in generated Helm chart output
- Drift between what's committed and what Nix produces

## ArgoCD Sync Trigger

The deploy job triggers ArgoCD to sync **all** Applications after applying bootstrap manifests. This ensures ArgoCD picks up any changes to Application CRs and reconciles the cluster state.

The flow:
1. `kubectl apply` — updates all Kubernetes resources (namespaces, deployments, ArgoCD Applications, etc.)
2. `POST /api/v1/applications/{name}/sync` — for each ArgoCD Application, triggers an immediate sync
3. ArgoCD pulls the latest from each Application's source repo and reconciles

## Adding New Tests

### Nix module unit tests

Add a `.test.nix` file in `tests/nix/` and register it in `modules/outputs/checks.nix` under `nixModuleTests`.

### Policy tests (Rego)

Edit `tests/policy/default.rego` to add new deny rules. These run via `conftest` as part of `nix flake check`.

### VM integration tests

Add a `.nix` file in `tests/vm/` using `pkgs.testers.nixosTest`. Register it in `modules/outputs/checks.nix` under the `lib.optionalAttrs (system == "x86_64-linux")` block.
