---
wave: 3
depends_on: [02]
files_modified:
  - (no new files — verification only)
autonomous: true
---

# Plan 03: Build Verification & Diff

## Objective
Verify that the refactored bootstrap produces the same output as the original (modulo the cloudflared route fix). Ensure `nix build .#bootstrap` and `nix flake check` pass.

## Context
Plans 01 and 02 perform a large mechanical refactoring. This plan verifies correctness by comparing the build output before and after.

**IMPORTANT**: Before executing this plan, capture the current bootstrap output:
```bash
cd /Users/benjamin/Personal/QuadNix && nix build .#bootstrap && cp result/bootstrap.yaml /tmp/bootstrap-before.yaml
```

## Tasks

### Task 1: Capture pre-refactor baseline

<read_first>
- modules/outputs/bootstrap.nix (current, to verify what we're comparing against)
</read_first>

<action>
Run the baseline capture before any changes are applied:
```bash
cd /Users/benjamin/Personal/QuadNix
nix build .#bootstrap
cp result/bootstrap.yaml /tmp/bootstrap-before.yaml
echo "Baseline captured: $(wc -l < /tmp/bootstrap-before.yaml) lines"
```

If this has already been done (file exists at `/tmp/bootstrap-before.yaml`), skip.
</action>

<acceptance_criteria>
- `/tmp/bootstrap-before.yaml` exists and is non-empty
- File contains `kind: Namespace` (valid K8s manifests)
- Command outputs line count
</acceptance_criteria>

### Task 2: Build refactored bootstrap and compare

<read_first>
- modules/outputs/bootstrap/default.nix (the new orchestrator)
- modules/outputs/bootstrap/cloudflared.nix (verify cloudflared routes)
</read_first>

<action>
Build the refactored bootstrap:
```bash
cd /Users/benjamin/Personal/QuadNix
nix build .#bootstrap
cp result/bootstrap.yaml /tmp/bootstrap-after.yaml
```

Compare with baseline:
```bash
diff /tmp/bootstrap-before.yaml /tmp/bootstrap-after.yaml > /tmp/bootstrap-diff.txt 2>&1 || true
```

Expected differences (from the cloudflared route fix):
1. K8s cloudflared config now uses port 30856 instead of port 80 — this is the INTENTIONAL fix
2. Cloudflared config content may differ in formatting (JSON vs YAML ordering) — acceptable
3. All other content should be identical

Review the diff:
```bash
wc -l /tmp/bootstrap-diff.txt
cat /tmp/bootstrap-diff.txt
```

If the diff shows ONLY the expected cloudflared route changes (port 80 → 30856 in the K8s instance), the refactor is correct. If it shows unexpected differences, investigate and fix.
</action>

<acceptance_criteria>
- `nix build .#bootstrap` exits 0
- `/tmp/bootstrap-after.yaml` exists and is non-empty
- Diff output is limited to cloudflared route port changes (80 → 30856)
- No manifests are missing (same count of `---` separators)
- No manifests have reordered fields or missing content (outside cloudflared)
</acceptance_criteria>

### Task 3: Run flake checks

<read_first>
- modules/outputs/checks.nix (to understand what checks exist)
</read_first>

<action>
Run:
```bash
cd /Users/benjamin/Personal/QuadNix
nix flake check --no-build 2>&1 || true
```

Note: `--no-build` checks derivations without building (faster). If that's not supported, run without it but expect longer execution.

Also verify the individual file outputs still exist:
```bash
ls result/ | head -20
```
</action>

<acceptance_criteria>
- `nix flake check` succeeds or shows only pre-existing failures (not new ones introduced by refactor)
- All numbered YAML files are present in the output (00-metallb.yaml through 17e-openclaw-ingress.yaml)
- `bootstrap.yaml` (combined file) exists in output
</acceptance_criteria>

### Task 4: Verify cloudflared route consistency

<read_first>
- modules/roles/backbone.nix (host cloudflared — now uses shared options)
- modules/outputs/bootstrap/cloudflared.nix (K8s cloudflared — now uses shared options)
- modules/shared/cloudflared-routes.nix (the single source of truth)
</read_first>

<action>
Verify both cloudflared instances produce consistent configs:

1. Check host config (backbone.nix) uses the shared route list:
```bash
grep -c "ingress" /Users/benjamin/Personal/QuadNix/modules/roles/backbone.nix
# Should NOT contain individual route entries — only references to config.quad.cloudflared.*
```

2. Check K8s configmap uses port 30856:
```bash
grep "30856" /tmp/bootstrap-after.yaml | head -5
```

3. Verify no port 80 routes remain in the K8s cloudflared config:
```bash
# Extract the cloudflared configmap section and check for port 80
grep -A 50 "name: cloudflared-config" /tmp/bootstrap-after.yaml | grep "http://127.0.0.1:80" && echo "FAIL: port 80 still found" || echo "OK: no port 80 routes"
```

4. Verify both configs have the same set of hostnames:
```bash
# Host side hostnames
grep "hostname" /Users/benjamin/Personal/QuadNix/modules/shared/cloudflared-routes.nix | sort

# K8s side hostnames (from configmap)
grep "hostname" /tmp/bootstrap-after.yaml | head -20
```
</action>

<acceptance_criteria>
- `backbone.nix` does NOT contain inline hostname→service mappings
- K8s cloudflared configmap contains `http://127.0.0.1:30856` for all HTTP routes
- No `http://127.0.0.1:80` entries in K8s cloudflared config
- Both configs list the same hostnames (same count, same domains)
- The shared options module `cloudflared-routes.nix` is the ONLY place routes are defined
</acceptance_criteria>

## must_haves (Goal-Backward Verification)
- [ ] `nix build .#bootstrap` succeeds
- [ ] Output YAML is functionally equivalent to pre-refactor (modulo cloudflared fix)
- [ ] Cloudflared K8s deployment uses port 30856, not port 80
- [ ] All 15+ sub-modules exist and are individually readable
- [ ] `default.nix` is under 150 lines
- [ ] No cloudflared routes are hardcoded in backbone.nix or bootstrap sub-modules
