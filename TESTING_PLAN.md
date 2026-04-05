# Testing & Versioning Plan

This document defines the quality strategy for QuadNix — covering both **OS-level changes** (NixOS host configurations) and **cluster-level changes** (Kubernetes manifests, Helm charts, ArgoCD applications).

## Current State

| Area | What exists | Gaps |
|---|---|---|
| NixOS host config | `evalModules` tree, `mkClusterHost`, deploy-rs | No `nix flake check`, no VM tests, no build gate |
| Nix module unit tests | 8 `.test.nix` files in `tests/nix/` (assertion-based) | Not wired into `checks` output, run manually |
| Kubernetes / Helm | `nixhelm` + `nix-kube-generators`, ArgoCD bootstrap YAML | Giant inline heredoc in `flake.nix`, no diffing, no policy checks |
| CI | One Forgejo Actions workflow (`.forgejo/workflows/`) | Only builds charts + publishes, doesn't validate NixOS configs or run existing tests |
| Versioning | Git (no tags, no changelog) | No semantic versioning, no release process, `flake.lock` is the only pin |

---

## Architecture

The single quality gate is **`nix flake check`**. Everything plugs into it:

```
nix flake check
├── checks.formatting          (alejandra / nixfmt)
├── checks.unit.*              (8 existing .test.nix files)
├── checks.manifests.*         (kubeconform on bootstrap YAML)
├── checks.policy.*            (conftest / OPA on manifests)
├── checks.vm.*                (NixOS VM integration tests)
└── nixosConfigurations build  (eval succeeds for all 4 hosts)
```

CI (`Forgejo Actions`) runs `nix flake check` on every push. Deployment only proceeds after checks pass on `main`.

---

## Layer 1 — Wire Existing Tests into Flake Checks

The `tests/nix/**/*.test.nix` files are standalone Nix expressions that return `true`. They must be exposed as flake `checks`.

### What to do

Add a `checks` output to `flake.nix`:

```nix
checks = forAllSystems (system:
  let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in
  {
    quad-mk-cluster-host = pkgs.runCommand "test-quad-mk-cluster-host" {} ''
      ${pkgs.nix}/bin/nix-instantiate --eval ${./tests/nix/quad/mk-cluster-host.test.nix} \
        --arg pkgs 'import ${inputs.nixpkgs} { system = "${system}"; }'
      echo pass > $out
    '';

    quad-hosts-output = pkgs.runCommand "test-quad-hosts-output" {} ''
      ${pkgs.nix}/bin/nix-instantiate --eval ${./tests/nix/quad/hosts-output.test.nix} \
        --arg pkgs 'import ${inputs.nixpkgs} { system = "${system}"; }'
      echo pass > $out
    '';

    shared-common = pkgs.runCommand "test-shared-common" {} ''
      ${pkgs.nix}/bin/nix-instantiate --eval ${./tests/nix/shared/common.test.nix} \
        --arg pkgs 'import ${inputs.nixpkgs} { system = "${system}"; }'
      echo pass > $out
    '';

    shared-forgejo-common = pkgs.runCommand "test-shared-forgejo-common" {} ''
      ${pkgs.nix}/bin/nix-instantiate --eval ${./tests/nix/shared/forgejo-common.test.nix} \
        --arg pkgs 'import ${inputs.nixpkgs} { system = "${system}"; }'
      echo pass > $out
    '';

    forgejo-server = pkgs.runCommand "test-forgejo-server" {} ''
      ${pkgs.nix}/bin/nix-instantiate --eval ${./tests/nix/forgejo/server.test.nix} \
        --arg pkgs 'import ${inputs.nixpkgs} { system = "${system}"; }'
      echo pass > $out
    '';

    forgejo-runner = pkgs.runCommand "test-forgejo-runner" {} ''
      ${pkgs.nix}/bin/nix-instantiate --eval ${./tests/nix/forgejo/runner.test.nix} \
        --arg pkgs 'import ${inputs.nixpkgs} { system = "${system}"; }'
      echo pass > $out
    '';

    k8s-control-plane = pkgs.runCommand "test-k8s-control-plane" {} ''
      ${pkgs.nix}/bin/nix-instantiate --eval ${./tests/nix/kubernetes/control-plane.test.nix} \
        --arg pkgs 'import ${inputs.nixpkgs} { system = "${system}"; }'
      echo pass > $out
    '';

    k8s-worker = pkgs.runCommand "test-k8s-worker" {} ''
      ${pkgs.nix}/bin/nix-instantiate --eval ${./tests/nix/kubernetes/worker.test.nix} \
        --arg pkgs 'import ${inputs.nixpkgs} { system = "${system}"; }'
      echo pass > $out
    '';
  }
);
```

### How to run

```bash
nix flake check            # runs all checks
nix flake check .#x86_64-linux  # per-system
```

---

## Layer 2 — NixOS VM Integration Tests

NixOS has a built-in QEMU VM test framework (`pkgs.nixosTest`). It boots real VMs and asserts systemd services start correctly. This catches regressions that module-level tests cannot.

### What to test

| Test name | What it validates |
|---|---|
| `vm-backbone-control-plane` | `kube-apiserver`, `etcd`, `containerd`, `flannel` all start; `kubectl get nodes` returns a node |
| `vm-frontline-worker` | `kubelet` starts, `containerd` is running |
| `vm-sops-decrypt` | sops-nix decrypts secrets at activation time |

### Example

```nix
# tests/vm/control-plane.nix
{ pkgs, inputs }:
pkgs.nixosTest {
  name = "backbone-control-plane";
  nodes.backbone = { config, ... }: {
    imports = [
      inputs.sops-nix.nixosModules.sops
      ./modules/shared/quad-common.nix
      ./modules/profiles/kubernetes/control-plane.nix
    ];
    # Mock hardware, disable cloudflared, provide test certs
    boot.loader.grub.enable = false;
    fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
    services.cloudflared.enable = lib.mkForce false;
  };

  testScript = ''
    backbone.start()
    backbone.wait_for_unit("containerd.service")
    backbone.wait_for_unit("etcd.service")
    backbone.wait_for_unit("kube-apiserver.service")
    backbone.succeed("kubectl cluster-info")
  '';
}
```

Add to `checks` — these run in ~1-3 minutes each.

### Package

`pkgs.nixosTest` — built into nixpkgs, no extra flake input needed.

---

## Layer 3 — Kubernetes Manifest Validation

### 3a. Schema validation with `kubeconform`

Validate every YAML document in the bootstrap against the Kubernetes OpenAPI schema:

```nix
# In checks
manifests-valid = pkgs.runCommand "validate-bootstrap-manifests" {
  nativeBuildInputs = [ pkgs.kubeconform ];
} ''
  kubeconform -summary -kubernetes-version 1.29 ${inputs.self.packages.${system}.bootstrap}/bootstrap.yaml
  touch $out
'';
```

### 3b. Policy checking with `conftest`

Enforce cluster policies using Rego:

```
# tests/policy/default.rego
package main

deny[msg] {
  input.kind == "Deployment"
  not input.metadata.labels.app
  msg := sprintf("Deployment '%s' missing app label", [input.metadata.name])
}

deny[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  container.securityContext.runAsUser == 0
  msg := sprintf("Container '%s' in Deployment '%s' runs as root", [container.name, input.metadata.name])
}
```

```nix
manifests-policy = pkgs.runCommand "policy-check-bootstrap" {
  nativeBuildInputs = [ pkgs.conftest ];
} ''
  mkdir -p policy
  cp ${./tests/policy/default.rego} policy/default.rego
  conftest test -p policy ${inputs.self.packages.${system}.bootstrap}/bootstrap.yaml
  touch $out
'';
```

### 3c. Manifest diffing

Detect unexpected changes to bootstrap manifests:

```bash
# Compare current bootstrap output against committed reference
nix build .#bootstrap.x86_64-linux
diff result/bootstrap.yaml docs/reference-bootstrap.yaml
```

To generate/update the reference:

```bash
nix build .#bootstrap.x86_64-linux && cp result/bootstrap.yaml docs/reference-bootstrap.yaml
```

---

## Layer 4 — CI Pipeline (Forgejo Actions)

Rewrite `.forgejo/workflows/build.yaml` with proper stages:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  nix-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install Nix
        uses: cachix/install-nix-action@v30
        with:
          extra_nix_config: |
            accept-flake-config = true

      - name: Check Nix formatting
        run: nix fmt -- --check .

      - name: Run all flake checks
        run: nix flake check --all-systems

      - name: Build all NixOS configurations
        run: |
          nix build .#nixosConfigurations.backbone-01.config.system.build.toplevel
          nix build .#nixosConfigurations.backbone-02.config.system.build.toplevel

  validate-manifests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Nix
        uses: cachix/install-nix-action@v30

      - name: Build and validate bootstrap manifests
        run: |
          nix build .#bootstrap.x86_64-linux
          nix run nixpkgs#kubeconform -- -summary -kubernetes-version 1.29 result/bootstrap.yaml

  deploy:
    needs: [nix-check, validate-manifests]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Nix
        uses: cachix/install-nix-action@v30

      - name: Deploy backbone-01
        run: nix run github:serokell/deploy-rs -- .#backbone-01 --skip-checks
```

### Key design decisions

- `nix flake check` is the single quality gate — all module tests, VM tests, manifest validation, and formatting run through it
- NixOS configs are **built** (not deployed) to catch eval errors
- Deployment only happens on `main` after all checks pass
- Use `self-hosted` runner labels if Forgejo runners are on the cluster itself

---

## Layer 5 — Versioning & Release Strategy

### Semantic versioning via Git tags

```
v<major>.<minor>.<patch>
```

| Change type | Bump | Example |
|---|---|---|
| New service or K8s application added | minor | `v1.1.0` |
| Helm chart version upgrade | minor | `v1.2.0` |
| NixOS config tweak (port, flag, package) | patch | `v1.2.1` |
| Breaking change (node removal, k8s version upgrade) | major | `v2.0.0` |

### `flake.lock` management

`flake.lock` is the dependency pin — treat it like `package-lock.json`:

- **Never** run `nix flake update` without committing the result
- Run full updates on a deliberate cadence (weekly or biweekly)
- Pin specific inputs for targeted updates: `nix flake lock --update-input nixpkgs`

### Git tags and changelog

```bash
# Tag a release
git tag -a v1.3.0 -m "Add Harbor registry, upgrade ArgoCD to v2.10"
git push --tags

# Generate changelog from conventional commits
nix run nixpkgs#git-cliff
```

### Formatting

Add a `formatter` output to `flake.nix`:

```nix
formatter = forAllSystems (system:
  inputs.nixpkgs.legacyPackages.${system}.alejandra
);
```

Then run with `nix fmt`. CI checks formatting with `nix fmt -- --check .`.

---

## Implementation Priority

| Priority | Task | Effort | Impact |
|---|---|---|---|
| **P0** | Wire `.test.nix` files into `checks` output | 1 hour | Every push validates modules |
| **P0** | Add `formatter` output (`alejandra`) | 30 min | Consistent Nix code style |
| **P1** | Add `kubeconform` check on bootstrap manifests | 1 hour | Catch invalid K8s YAML before deploy |
| **P1** | Rewrite Forgejo Actions CI with `nix flake check` | 2 hours | Automated quality gate on every push |
| **P2** | Extract bootstrap heredoc into proper Nix modules | 3 hours | Maintainability + testability |
| **P2** | Add NixOS VM test for control-plane | 3 hours | Catch systemd service regressions |
| **P3** | Conftest/OPA policy checks | 2 hours | Enforce cluster-wide policies |
| **P3** | Git tags + `git-cliff` changelog | 1 hour | Track infrastructure versions |

---

## Packages and Tools

| Tool | Source | Purpose |
|---|---|---|
| `nix flake check` | Built into Nix | Single entry point for all validation |
| `pkgs.nixosTest` | nixpkgs | VM-level integration tests for NixOS configs |
| `kubeconform` | nixpkgs | Validate K8s manifests against OpenAPI schema |
| `conftest` | nixpkgs | Rego-based policy checks on YAML manifests |
| `alejandra` | nixpkgs | Nix code formatting (`formatter` flake output) |
| `deploy-rs` | Already in flake inputs | Declarative deployment with rollback |
| `git-cliff` | nixpkgs | Changelog generation from conventional commits |
| `sops-nix` | Already in flake inputs | Secret management (test decryption in VM tests) |
| Forgejo Actions | Already configured | CI runner infrastructure |
