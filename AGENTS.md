## QuadNix Agent Notes

- **Deploy (deploy-rs)**: `nix run github:serokell/deploy-rs -- .#backbone-01 --skip-checks`
- **Host definitions**: live in `modules/hosts/*.nix` using `config.quad.lib.mkClusterHost`
- **Core roles**: `modules/roles/backbone.nix`, `modules/roles/frontline.nix`
- **Profiles**: `modules/profiles/*` (base, server, docker, kubernetes)
- **Services**: `modules/services/*`
- **Shared options**: `modules/shared/*` (quad/k8s/forgejo)
- **Outputs**: `modules/outputs/*` (nixosConfigurations, deploy, helm)

to run kubectl commands, prepend with `set -gx KUBECONFIG /etc/kubernetes/cluster-admin.kubeconfig` the commands that you will run inside of ssh host backbone01
MAKE SURE ALL FIXES ARE DECLARATIVE DO NOT IMPLEMENT IMPERATIVE CHANGES WITHOUT PUTTING THEM INTO THIS REPO

## Versioning & Changelog (git-cliff)

This repo uses [git-cliff](https://git-cliff.org) for changelog generation from conventional commits.

### Conventional commit format

All commits landing on `main` should follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>
```

Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `ci`
Scopes: `backbone`, `frontline`, `argocd`, `harbor`, `erpnext`, `helm`, `flake`, `k8s`, `secrets`, `forgejo`, `docs`

Examples:
```
feat(argocd): upgrade ArgoCD to v2.10
fix(backbone): increase etcd startup timeout to 120s
chore(flake): update nixpkgs to 2026-04-01
feat(harbor): add Harbor registry via ArgoCD
refactor(k8s): extract bootstrap manifests into modular Nix files
```

### Generating the changelog

```bash
# Preview changelog for unreleased changes
nix run nixpkgs#git-cliff -- --config cliff.toml --workdir .

# Bump version and append to CHANGELOG.md
nix run nixpkgs#git-cliff -- --config cliff.toml --tag v1.3.0 --workdir .
```

### Tagging a release

```bash
git tag -a v1.3.0 -m "feat(argocd): upgrade to v2.10, add Harbor registry"
git push --tags
nix run nixpkgs#git-cliff -- --config cliff.toml --tag v1.3.0 --workdir .
```

### Version bump guidelines

| Change | Bump |
|---|---|
| New service or K8s application | minor |
| Helm chart version upgrade | minor |
| NixOS config tweak (port, flag, package) | patch |
| Breaking change (node removal, k8s version upgrade) | major |
