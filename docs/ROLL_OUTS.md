# Rollouts and Environments

This repo manages two planes:

- **Hosts**: NixOS machines (backbone/frontline)
- **Kubernetes**: Cluster services and applications

## Host Rollouts (NixOS)

Recommended flow:

1. Update host configuration in `modules/hosts/` + related profiles/services.
2. Build locally or in CI:
   ```sh
   nix build .#nixosConfigurations.<host>.config.system.build.toplevel
   ```
3. Deploy with deploy-rs:
   ```sh
   nix run github:serokell/deploy-rs -- .#<host>
   ```

Use `remoteBuild = true;` in the host definition when the host should build on itself.

## Kubernetes Rollouts (Bootstrap + ArgoCD)

Recommended flow:

1. Build bootstrap manifests from the flake:
   ```sh
   nix build .#bootstrap.x86_64-linux
   ```
2. Apply to the cluster:
   ```sh
   kubectl apply --server-side --field-manager=quadnix -f result/bootstrap.yaml
   ```
3. Let ArgoCD manage application sync thereafter.

Keep bootstrap focused on cluster-level infra and cluster services.
Apps should be deployed by ArgoCD from app repos.

## Where to Put App Manifests

Keep Kubernetes manifests **with each app** (current pattern):

- `../edukurs/k8s`
- `../quadpacient/k8s`
- `../orkestr/k8s`

This keeps ownership close to the app, and works well with ArgoCD. For cross-app shared policies
or base components, use a separate repo or a `k8s-base/` folder in this repo and reference it from
app overlays.

## Suggested Folder Responsibilities

- `modules/hosts/`: host definitions
- `modules/roles/` and `modules/profiles/`: host behavior and system services
- `modules/outputs/bootstrap.nix`: cluster infra bootstrap
- app repos `k8s/`: app manifests (referenced by ArgoCD Applications)

## Promotion Strategy (Simple)

- Use ArgoCD Projects with `dev`/`staging`/`prod` namespaces.
- Branch-based sync rules (e.g., `main` -> prod, `develop` -> staging).
- Keep secrets in SOPS in each repo or a centralized secrets repo.
