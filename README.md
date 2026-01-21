# NixOS Configuration

A battle-tested NixOS configuration structure for multi-server deployments.

## Structure Overview

```
nixos/
├── flake.nix              # Flake entry point with host definitions
├── flake.lock             # Locked dependencies
├── lib/
│   └── mkHost.nix         # Helper to build host configurations
├── hosts/
│   ├── backbone-01/       # Control plane node
│   ├── backbone-02/       # Control plane node (HA)
│   ├── frontline-01/      # Worker node
│   └── frontline-02/      # Worker node
├── roles/
│   ├── backbone.nix       # Control plane role
│   └── frontline.nix      # Worker role
├── profiles/
│   ├── base.nix           # Base configuration (all hosts)
│   ├── server.nix         # Server defaults
│   ├── docker.nix         # Docker runtime
│   └── kubernetes/        # K8s control-plane/worker profiles
├── services/
│   ├── gitea.nix          # Git service
│   ├── clickhouse.nix     # Logging backend
│   ├── otel.nix           # OpenTelemetry
│   ├── buildkite.nix      # CI/CD
│   └── ingress.nix        # Ingress controller
└── secrets/
    └── sops.nix           # SOPS integration
```

## Getting Started

### 1. Generate Hardware Configs

For each host, run on the target machine:

```bash
nixos-generate-config --show-hardware-config > hosts/<hostname>/hardware.nix
```

### 2. Add SSH Keys

Edit `profiles/base.nix` and replace the placeholder with your public key.

### 3. Initialize Flake

```bash
cd nixos
nix flake update
```

### 4. Deploy to a Host

```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

Replace `<hostname>` with: `backbone-01`, `backbone-02`, `frontline-01`, or `frontline-02`.

## Next Steps

- **K3s vs kubeadm**: Currently set up for kubeadm. For lightweight clusters, swap to k3s.
- **Deploy with deploy-rs**: Add deploy-rs for atomic deployments.
- **Add more services**: Create new files in `services/` and import in roles.
- **Secrets setup**: Initialize SOPS with `sops init` and create `secrets/secrets.yaml`.

## Key Principles

- **Role** = What the machine *does* (backbone vs frontline)
- **Profile** = How the machine *behaves* (base, server, docker)
- **Service** = What *runs* on the machine (gitea, k8s, etc.)
