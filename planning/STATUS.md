# QuadNix Planning — Status

**Date:** 2026-05-19

---

## Track 1: Bootstrap Refactor ✅ COMPLETE

**Goal:** Break `modules/outputs/bootstrap.nix` (1500 lines) into modular pieces. Golden test ensures byte-identical output.

**Output:** `bootstrap-refactor/` — 14 modules + golden test
**Status:** ✅ All 62 manifest files byte-identical to original

**Next step:** Wire `config.flake.bootstrap` to use refactored output. Parent session to drive this.

---

## Track 2: Machine DSL 📋 DESIGN DONE

**Goal:** Single `machines/default.nix` as source of truth for NixOS hosts.

**Output:** `planning/machines-dsl-design.md`
**Status:** 📋 Design complete. Implementation pending bootstrap-refactor Phase 1.

**What's defined:**
- Schema: `machines` attrset + `roles` attrset
- Role as key reference (`role = "backbone"`)
- Field reference (system, hardware, role, taints, extraModules, sshHost, remoteBuild)
- Migration path: 3 phases
- VPN defined in role module (not top-level DSL field)

**K8s resources:** NOT in scope. Handled by `bootstrap-refactor/`.

---

## Track 3: Headscale ⏸️ PARKED

**Goal:** Self-hosted VPN control plane to replace Tailscale SaaS.

**Output:** `planning/headscale-design.md` + `headscale/handoff.md` (detailed research)
**Status:** ⏸️ PARKING until static IP is available

**Reason:** Headscale's embedded DERP relay needs a public IP + port 443. No static IP = no self-hosted relay. Tailscale is fine for now.

**When to implement:**
1. Acquire static IP from ISP
2. Open ports 443 (HTTPS for DERP) + 3478/UDP (STUN)
3. Point `vpn.quadtech.dev` at static IP
4. Follow upgrade path in `planning/headscale-design.md`

**WireGuard fallback:** Also parked. Native WireGuard on backbone-01 (UDP 51820) is simpler but also needs a public IP for the server endpoint. Covered in `headscale/handoff.md`.

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

---

## Open Items

- [ ] Wire `config.flake.bootstrap` to use `bootstrap-refactor/default.nix`
- [ ] Remove `bootstrapRefactored` from flake.nix packages (rename to `bootstrap`)
- [ ] Implement machine DSL Phase 1 (create registry alongside existing system)
- [ ] Implement machine DSL Phase 2 (switch flake.nix to use registry)
- [ ] Implement machine DSL Phase 3 (cleanup old files)
- [ ] Get static IP from ISP
- [ ] Implement Headscale (after static IP)