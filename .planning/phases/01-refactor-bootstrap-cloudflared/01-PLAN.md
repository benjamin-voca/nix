---
wave: 1
depends_on: []
files_modified:
  - modules/shared/cloudflared-routes.nix
  - modules/imports.nix
  - modules/roles/backbone.nix
autonomous: true
---

# Plan 01: Shared Cloudflared Options & Backbone Integration

## Objective
Create a single source of truth for cloudflared tunnel configuration via NixOS options, then refactor `backbone.nix` to consume it instead of hardcoded inline YAML.

## Context
Currently cloudflared ingress routes are hardcoded in TWO places:
1. `modules/roles/backbone.nix` — host systemd cloudflared (preStart writes config.yaml inline)
2. `modules/outputs/bootstrap.nix` — K8s deployment (cloudflaredConfigContent variable)

Both must produce identical route lists. This plan creates the shared options and refactors the host side (backbone.nix). The K8s side is addressed in Plan 02.

## Tasks

### Task 1: Create `modules/shared/cloudflared-routes.nix`

<read_first>
- modules/shared/quad-common.nix (pattern for shared option modules)
- modules/options/quad.nix (existing quad.* option namespace)
- modules/roles/backbone.nix (current cloudflared route list — the source of truth for routes)
- modules/outputs/bootstrap.nix (cloudflaredConfigContent — secondary source of truth to reconcile)
</read_first>

<action>
Create `modules/shared/cloudflared-routes.nix` with these NixOS options under `options.quad.cloudflared`:

1. `tunnelId` — type `str`, no default (must be set)
2. `metricsPort` — type `int`, default `2002`
3. `nodePort` — type `int`, default `30856`
4. `credentialsFile` — type `str`, default `"/etc/cloudflared/creds/credentials.json"`
5. `protocol` — type `str`, default `"http2"`
6. `ingressRules` — type `listOf (attrsOf anything)`, description "Shared cloudflared ingress rules — single source of truth"

Then in `config` section, set the DEFAULT ingress rules by reconciling the two current sources:

The combined route list (from both backbone.nix and bootstrap.nix, deduplicated) should be:

```
{ hostname = "backbone-01.quadtech.dev"; service = "ssh://127.0.0.1:22"; }
{ hostname = "forge-ssh.quadtech.dev"; service = "tcp://127.0.0.1:32222"; }
{ hostname = "forge.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "argocd.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "helpdesk.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "harbor.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "educourses-pd.com"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "www.educourses-pd.com"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "verdaccio.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "minecraft.quadtech.dev"; service = "tcp://127.0.0.1:25565"; }
{ hostname = "edukurs.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "batllavatourist.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "quadpacienti.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "openclaw.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "grafana.k8s.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "grafana.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "api.orkestr-os.com"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ hostname = "*.quadtech.dev"; service = "http://127.0.0.1:${toString cfg.nodePort}"; }
{ service = "http_status:404"; }
```

Note: The catch-all `http_status:404` has no hostname key.

Also add a helper option `config.quad.cloudflared.configYaml` that generates the full config as a YAML string (using `builtins.toJSON`), consuming `tunnelId`, `credentialsFile`, `metricsPort`, `protocol`, and `ingressRules`. This can be used by both the host systemd service and K8s configmap.
</action>

<acceptance_criteria>
- `modules/shared/cloudflared-routes.nix` exists and is valid Nix
- File defines `options.quad.cloudflared` with all 6 options listed above
- File defines `config.quad.cloudflared.configYaml` as a computed string
- `config.quad.cloudflared.ingressRules` contains all routes from both current sources (deduplicated)
- All HTTP routes use `"http://127.0.0.1:" + toString cfg.nodePort` (port 30856 by default), NOT port 80
- The SSH route uses `"ssh://127.0.0.1:22"`
- The Forge SSH route uses `"tcp://127.0.0.1:32222"`
- The Minecraft route uses `"tcp://127.0.0.1:25565"`
- The catch-all is `{ service = "http_status:404"; }` with no hostname
</acceptance_criteria>

### Task 2: Add `modules/shared/` to `imports.nix`

<read_first>
- modules/imports.nix
</read_first>

<action>
In `modules/imports.nix`, add `filesIn ./shared` to the list of auto-imported directories. The current list is:

```nix
filesIn ./options
++ filesIn ./outputs
++ filesIn ./hosts
++ filesIn ./lib
```

Change to:

```nix
filesIn ./options
++ filesIn ./outputs
++ filesIn ./hosts
++ filesIn ./lib
++ filesIn ./shared
```
</action>

<acceptance_criteria>
- `modules/imports.nix` contains `filesIn ./shared`
- The file still has all original imports (`./options`, `./outputs`, `./hosts`, `./lib`)
</acceptance_criteria>

### Task 3: Refactor `backbone.nix` cloudflared to use shared options

<read_first>
- modules/roles/backbone.nix (current hardcoded cloudflared)
- modules/shared/cloudflared-routes.nix (the new shared options, created in Task 1)
</read_first>

<action>
Replace the entire cloudflared configuration block in `backbone.nix` with a version that consumes `config.quad.cloudflared.*`.

Specifically:

1. Set `config.quad.cloudflared.tunnelId = "b6bac523-be70-4625-8b67-fa78a9e1c7a5";`
2. Set `config.quad.cloudflared.metricsPort = 2003;` (host uses 2003, K8s uses 2002 — different to avoid conflicts when both run on same host)
3. Replace the `systemd.services.cloudflared.preStart` block. Instead of the giant `cat > config.yaml << EOF` with inline YAML, generate the config from `config.quad.cloudflared.configYaml`. Write it to `/etc/cloudflared/config/config.yaml` using `pkgs.writeText` or directly in the preStart script.

The new preStart should be something like:
```nix
systemd.services.cloudflared.preStart = ''
  mkdir -p /etc/cloudflared/config /etc/cloudflared/creds
  
  # Wait for the secret to be available
  for i in $(seq 1 30); do
    if [ -f /run/secrets/cloudflared-credentials.json ]; then
      break
    fi
    echo "Waiting for cloudflared credentials..."
    sleep 2
  done
  
  # Write config from shared source of truth
  cat > /etc/cloudflared/config/config.yaml << 'EOF'
  ${config.quad.cloudflared.configYaml}
  EOF
  
  # Copy credentials from SOPS secret
  cp /run/secrets/cloudflared-credentials.json /etc/cloudflared/creds/credentials.json
  chmod 600 /etc/cloudflared/creds/credentials.json
'';
```

4. Remove all the inline `ingress:` entries from the old preStart — they're now in the shared module.
5. The `sops.secrets.cloudflared-credentials` block stays in backbone.nix unchanged (it's host-specific).
6. Remove the `app.orkestr-os.com` entry from the backbone.nix inline config if it exists (it was only in bootstrap.nix, not backbone.nix's host config — keep the shared list authoritative).
</action>

<acceptance_criteria>
- `modules/roles/backbone.nix` no longer contains any inline `hostname:` cloudflared route entries
- `modules/roles/backbone.nix` contains `config.quad.cloudflared.tunnelId = "b6bac523-be70-4625-8b67-fa78a9e1c7a5"`
- `modules/roles/backbone.nix` contains `config.quad.cloudflared.metricsPort = 2003`
- `modules/roles/backbone.nix` `preStart` script references `config.quad.cloudflared.configYaml`
- The `systemd.services.cloudflared` ExecStart still uses `${pkgs.cloudflared}/bin/cloudflared tunnel --protocol http2 --config /etc/cloudflared/config/config.yaml run`
- `sops.secrets.cloudflared-credentials` block is unchanged
- All other backbone.nix content (sops secrets, services, packages) is unchanged
</acceptance_criteria>

## Verification
1. `nix-instantiate --eval --strict -E 'import ./modules/shared/cloudflared-routes.nix { lib = import <nixpkgs/lib>; }'` parses without error
2. The `quad.cloudflared.ingressRules` list contains the same routes that were previously hardcoded in both files
3. All HTTP ingress rules use port 30856 (the nodePort), not port 80
