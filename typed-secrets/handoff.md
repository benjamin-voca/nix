# Typed Secrets Phase 1 — Handoff

**Date:** 2026-05-19
**Status:** ✅ Phase 1 Complete

---

## What Was Created

### `lib/typed-secrets.nix` — Core Library
6 functions for compile-time secret validation:

| Function | Purpose |
|----------|---------|
| `toHyphenatedKey` | Convert dot-notation → hyphenated (e.g., `harbor.admin-password` → `harbor-admin-password`). No-op for already-hyphenated keys. |
| `hasKey` | Check if a SOPS file (content string) contains a given key. Uses `builtins.match` with `.*key:.*` pattern. |
| `resolveField` | Layered lookup: given `[{path, content}]` pairs, find which file contains a field. First match wins. |
| `readSopsContent` | Read a SOPS file into `{path, content}` pair. Returns empty content if file doesn't exist. |
| `validateRequired` | Takes a list of required fields + layered files, returns `[{field, sopsFile}]`. Throws if any field missing. |
| `toSopsSecrets` | Convert validated secrets into `sops.secrets` attrset format. Ready for NixOS config. |

### Layered Secrets Directory Structure
```
secrets/
├── shared.yaml              # Cluster-wide (EMPTY)
├── roles/
│   ├── backbone.yaml       # Backbone role (EMPTY)
│   └── worker.yaml         # Worker role (EMPTY)
└── hosts/
    ├── backbone-01.yaml     # Machine-specific (EMPTY)
    └── frontline-01.yaml   # Machine-specific (EMPTY)
```

All files are comment-only (no actual secrets migrated). Each file has a header explaining the layer and migration plan.

### `machines/default.nix` — Registry Updates

**Per-machine:** Added `secrets.files` — ordered list of layered SOPS files:
- `backbone-01`: `[shared.yaml, roles/backbone.yaml, hosts/backbone-01.yaml]`
- `frontline-01`: `[shared.yaml, roles/worker.yaml, hosts/frontline-01.yaml]`

**Per-role:** Added `requiredSecrets`:

#### Backbone (27 secrets)
```
cloudflared-credentials
forgejo-db-password, forgejo-admin-password, forgejo-runner-token, forgejo-agent-token
argocd-admin-password, argocd-forgejo-username, argocd-forgejo-token
harbor-admin-password, harbor-registry-password
ceph-rgw-s3-access-key, ceph-rgw-s3-secret-key
minecraft-rcon-password
verdaccio-admin-password
erpnext-db-admin-password, erpnext-admin-password
openclaw-gateway-token, openclaw-minimax-api-key, openclaw-discord-id
orkestr-db-password, orkestr-secret-key-base, orkestr-token-signing-secret, orkestr-electric-secret
librechat-zhipu-api-key, librechat-minimax-api-key, librechat-jwt-secret
tailscale-auth-key
```

#### Worker (1 secret)
```
cloudflared-credentials
```

### Documentation Updates
- `planning/STATUS.md` — Track 3 updated to 🔨 IN PROGRESS, open items updated, changelog added

---

## What Was NOT Changed (by design)

- **`machines/consumer.nix`** — NOT wired in. Typed secrets infrastructure is ready but not consumed yet.
- **`modules/roles/backbone.nix`** — Manual `sops.secrets` remains as-is.
- **`modules/roles/worker.nix`** — No `sops.secrets` (worker uses inline cloudflared config, not SOPS).
- **`secrets/backbone-01.yaml`** — Existing flat SOPS file unchanged.
- **`secrets/frontline-01.yaml`** — Existing flat SOPS file unchanged.

---

## Validation Results

```
✅ Library loads: nix-instantiate --eval lib/typed-secrets.nix → 6 functions
✅ toHyphenatedKey: "harbor.admin-password" → "harbor-admin-password"
✅ hasKey: correctly detects present/absent keys in multi-line content
✅ resolveField: correctly finds keys across layered files
✅ validateRequired: returns [{field, sopsFile}] pairs
✅ Registry eval: nix eval .#machines → secrets.files correct for both machines
✅ Backbone requiredSecrets: 27 secrets
✅ Worker requiredSecrets: ["cloudflared-credentials"]
✅ nix flake check: all checks passed
✅ Existing nixosConfigurations: backbone-01 and frontline-01 still build
```

---

## Notes on `hasKey` Implementation

`builtins.match` in Nix matches the ENTIRE string (POSIX regex). To search for a key in multi-line content, the pattern `.*key:.*` is used — in Nix regex, `.` matches `\n` (unlike most regex engines). This means the pattern will find the key anywhere in the file content, not just at the start.

The `lib.escapeRegex` is used on the key to handle any special regex characters in key names.

---

## Phase 2 Tasks (Next)

1. **Distribute secrets into layered files** — Move secrets from `secrets/backbone-01.yaml` into `shared.yaml`, `roles/backbone.yaml`, and `hosts/backbone-01.yaml` based on the layering model.
2. **Re-encrypt with SOPS** — Each layered file needs its own SOPS encryption.
3. **Wire `lib/typed-secrets.nix` into `machines/consumer.nix`** — Use `validateRequired` + `toSopsSecrets` to auto-generate `sops.secrets` from the registry.
4. **Remove manual `sops.secrets` from `modules/roles/backbone.nix`** — Once consumer generates them.
5. **Verify deployment** — Build and deploy both machines to confirm secrets are correctly mounted.

### Key Considerations for Phase 2
- SOPS encryption must be done per-file (each layered file gets its own SOPS metadata)
- The `readSopsContent` function reads raw file content — key checking will work on encrypted SOPS files because SOPS preserves the key structure in the encrypted YAML (keys are plaintext, values are encrypted)
- Need to decide which secrets go to which layer (shared vs role vs host)
