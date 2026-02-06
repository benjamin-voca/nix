# NixOS Configuration

A dendritic NixOS configuration structure for multi-server deployments.

## Structure Overview

```
.
├── flake.nix                # Flake entry point (evalModules)
├── flake.lock               # Locked dependencies
├── modules/                 # Dendritic top-level modules
│   ├── hosts/               # Host declarations (single file each)
│   ├── hardware/            # Hardware configs referenced by hosts
│   ├── roles/               # Role modules (backbone/frontline)
│   ├── profiles/            # Base/system/k8s profiles
│   ├── services/            # Service modules
│   ├── shared/              # Shared option modules
│   ├── outputs/             # Flake outputs (nixosConfigurations, deploy, helm)
│   └── lib/                 # Helpers (mkClusterHost)
└── secrets/                 # SOPS secrets
```

## Getting Started

### 1. Generate Hardware Configs

For each host, run on the target machine:

```bash
nixos-generate-config --show-hardware-config > modules/hardware/<hostname>.nix
```

### 2. Add SSH Keys

Edit `modules/profiles/base.nix` and replace the placeholder with your public key.

### 3. Initialize Flake

```bash
nix flake update
```

Cachix binary caches are automatically configured - no manual setup needed!

### 4. Deploy to a Host

```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

Replace `<hostname>` with: `backbone-01`, `backbone-02`, `frontline-01`, or `frontline-02`.

## Binary Caches (Cachix)

This flake includes declarative Cachix configuration for faster builds:

- **nixhelm** - Pre-built Helm charts (instant downloads)
- **nix-community** - Community packages and tools

No manual `cachix use` commands needed - everything is configured declaratively in the flake.

See `docs/CACHIX.md` for details.

## Helm Charts Integration

This project integrates [nixhelm](https://github.com/farcaller/nixhelm) for declarative Helm chart management:

```nix
# Access any chart from nixhelm
nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd

# Use pre-configured charts
let
  helmCharts = inputs.self.helmCharts.x86_64-linux;
in {
  environment.systemPackages = [ helmCharts.argocd ];
}
```

See `lib/helm/README.md` for complete documentation and examples.

## Next Steps

- **K3s vs kubeadm**: Currently set up for kubeadm. For lightweight clusters, swap to k3s.
- **Deploy with deploy-rs**: Use `nix run github:serokell/deploy-rs -- .#backbone-01 --skip-checks`.
- **Add more services**: Create new files in `modules/services/` and import in roles.
- **Secrets setup**: Initialize SOPS with `sops init` and create `secrets/secrets.yaml`.
- **Helm charts**: Explore pre-configured charts in `lib/helm/charts/` or add your own.

## Key Principles

- **Role** = What the machine *does* (backbone vs frontline)
- **Profile** = How the machine *behaves* (base, server, docker)
- **Service** = What *runs* on the machine (gitea, k8s, etc.)
