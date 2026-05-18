# QuadNix Planning — Status

**Date:** 2026-05-19

---

## Track 1: Bootstrap Refactor ✅ COMPLETE

**Goal:** Break `modules/outputs/bootstrap.nix` (1500 lines) into modular pieces. Golden test ensures byte-identical output.

**Output:** `modules/outputs/bootstrap/` — 14 modular files + `modules/outputs/default.nix` + golden test
**Status:** ✅ All 62 manifest files byte-identical to original

**Next step:** Wire `config.flake.bootstrap` to use `modules/outputs/default.nix` output. Rename `bootstrapRefactored` → `bootstrap`.

---

## Track 2: Machine DSL 🚧 PHASE 1 COMPLETE

**Goal:** Single `machines/default.nix` as source of truth for NixOS hosts.

**Output:** `planning/machines-dsl-design.md` + `machines-dsl/handoff.md`
**Status:** ✅ Phase 1 complete — registry created alongside existing system

**What's done (Phase 1):**
- `machines/default.nix` — machine + role registry with all hosts
- `machines/consumer.nix` — NixOS module bridge (reads registry → config.quad.hosts)
- `machines/hardware/` → symlink to `modules/hardware/`
- `machines/roles/` → symlink to `modules/roles/`
- `modules/roles/worker.nix` — renamed from frontline.nix
- `tests/nix/machines/registry-test.nix` — structural validation
- Existing `nixosConfigurations` unchanged, all checks pass

**Architecture note:** consumer.nix lives in `machines/` (not `modules/lib/`) because `imports.nix` auto-discovers all `.nix` files in `modules/lib/`.

**Next steps:**
- Phase 2: Wire consumer.nix into `imports.nix`, add `machines` flake output, golden test
- Phase 3: Delete old `modules/hosts/*.nix`, cleanup

**K8s resources:** NOT in scope. Handled by `modules/outputs/bootstrap/`.

---

## Track 3: Typed Secrets 📋 DESIGN DONE

**Goal:** Compile-time validation of SOPS secrets with layering (shared → role → host overrides).

**Output:** `planning/typed-secrets-design.md`
**Status:** 📋 Design complete. Implementation deferred to machine DSL Phase 4.

**Key features:**
- Dot-notation field paths (`harbor.admin-password`)
- Layered files: shared.yaml → role.yaml → host.yaml (later wins)
- Compile-time error if required secret field missing
- `lib/typed-secrets.nix` core library

---

## Track 4: Headscale ⏸️ PARKED

**Goal:** Self-hosted VPN control plane to replace Tailscale SaaS.

**Output:** `planning/headscale-design.md` + `headscale/handoff.md` (detailed research)
**Status:** ⏸️ PARKING until static IP is available

**Reason:** Headscale's embedded DERP relay needs a public IP + port 443. No static IP = no self-hosted relay. Tailscale is fine for now.

**When to implement:**
1. Acquire static IP from ISP
2. Open ports 443 (HTTPS for DERP) + 3478/UDP (STUN)
3. Point `vpn.quadtech.dev` at static IP
4. Follow upgrade path in `planning/headscale-design.md`

---

## Resolved Decisions

| Decision | Outcome |
|----------|---------|
| K8s resources at machine level? | ❌ No — cluster-wide only |
| `index.nix` vs `default.nix`? | `default.nix` — Nix convention |
| Role as key reference? | ✅ Yes |
| Rename `frontline` → `worker`? | ✅ Yes |
| Headscale now or later? | Later — park until static IP |
| Cloudflare Tunnel removed? | ❌ No — stays for HTTP ingress |
| Secret field format? | Dot-notation (`harbor.admin-password`) |
| Secret layering? | shared.yaml → role.yaml → host.yaml |

---

## Open Items

- [ ] Wire `config.flake.bootstrap` to use `modules/outputs/default.nix` (rename to `bootstrap`)
- [x] Implement machine DSL Phase 1 (create registry alongside existing system)
- [ ] Implement machine DSL Phase 2 (switch flake.nix to use registry)
- [ ] Implement machine DSL Phase 3 (cleanup old files)
- [ ] Implement typed secrets Phase 1 (lib/typed-secrets.nix)
- [ ] Implement typed secrets Phase 2 (migrate secrets layout)
- [ ] Get static IP from ISP
- [ ] Implement Headscale (after static IP)

---

## Changelog

### 2026-05-19
- ✅ Complete bootstrap refactor (14 modules + golden test)
- ✅ Complete machine DSL Phase 1 (registry + consumer + test + role rename)
- 📋 Complete machine DSL design
- 📋 Complete typed secrets design
- ⏸️ Park Headscale until static IP
- 📋 Update planning/STATUS.md