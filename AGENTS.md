## QuadNix Agent Notes

- **Deploy (deploy-rs)**: `nix run github:serokell/deploy-rs -- .#backbone-01 --skip-checks`
- **Machine registry**: `machines/default.nix` — source of truth for all hosts and roles
- **Machine consumer**: `machines/consumer.nix` — bridges registry into NixOS module system
- **Core roles**: `modules/roles/backbone.nix`, `modules/roles/worker.nix`
- **Profiles**: `modules/profiles/*` (base, server, docker, kubernetes)
- **Services**: `modules/services/*`
- **Shared options**: `modules/shared/*` (quad/k8s/forgejo)
- **Outputs**: `modules/outputs/*` (nixosConfigurations, deploy, helm, bootstrap)

### Adding a new machine
1. Add entry to `machines/default.nix` under `machines` attrset
2. Create hardware module in `modules/hardware/<name>.nix`
3. If new role, add to `roles` attrset and create `modules/roles/<role>.nix`
4. Run `nix flake check` to verify

### Evaluating the registry
```bash
nix eval .#machines.machines --apply 'x: builtins.attrNames x' --json
nix eval .#machines.machines.backbone-01.role --json
nix eval .#machines.roles --apply 'x: builtins.attrNames x' --json
```

to run kubectl commands, prepend with `set -gx KUBECONFIG /etc/kubernetes/cluster-admin.kubeconfig` the commands that you will run inside of ssh host backbone01
MAKE SURE ALL FIXES ARE DECLARATIVE DO NOT IMPLEMENT IMPERATIVE CHANGES WITHOUT PUTING THEM INTO THIS REPO
- **kubectl**: works directly from the dev machine (macOS). Use `kubectl` locally, NOT via SSH.
- **Build platform**: dev machine is `aarch64-darwin`. Always build with `.#<output>.aarch64-darwin` (e.g. `nix build .#bootstrapInfra.aarch64-darwin`). Hosts are `x86_64-linux` — use deploy-rs with `remoteBuild = true` for cross-compilation.
- **No hardcoded IPs**: Avahi/mDNS resolves `.local` hostnames across the LAN. Do NOT add `networking.hosts` entries for cluster nodes.

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
fix(backbone): increase etetcd startup timeout to 120s
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
