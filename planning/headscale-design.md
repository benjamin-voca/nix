# Headscale — Research & Design

**Date:** 2026-05-19
**Status:** PARKING until static IP is available.

---

## TL;DR

Headscale replaces the Tailscale control plane. Tailscale clients (all devices) stay the same — just change the `--login-server` URL. This gives you DERP relay, MagicDNS, and ACLs with zero vendor dependency.

**But:** Headscale's embedded DERP relay needs a public IP/port. No static IP = no embedded DERP. Tailscale's public DERP servers are still available even with a self-hosted Headscale, so you can migrate without a public IP — but you're still using Tailscale's relay.

**Decision:** Park until static IP. Tailscale is fine for now.

---

## 1. What You Get vs What You Need

| | What Headscale gives | What it needs |
|---|---|---|
| Control plane | ✅ Self-hosted | K8s pod + SQLite |
| DERP relay | ✅ Built-in | **Public IP + port 443/3478** |
| Tailscale clients | ✅ Same clients, just different server URL | None |
| ACLs / MagicDNS | ✅ Same as Tailscale | Headscale control plane reachable |

## 2. Upgrade Path

```
Now                          Later (static IP)
─────────────────────────    ─────────────────────────────────────
Tailscale SaaS control    →   Headscale self-hosted control
plane (for coordination)      (vpn.quadtech.dev)

Tailscale public DERP     →   Your own embedded DERP relay
(relay when UDP fails)        (public IP + port 443)

Same Tailscale clients   →   Same Tailscale clients
Same SSH access          →   Same SSH access + DERP fallback
```

**No change to clients except:** `tailscale up --login-server=https://vpn.quadtech.dev`

## 3. NixOS Module Design

Pre-designed in `planning/headscale-research.md`. Key files:

```
modules/profiles/headscale-client.nix   # VPN client profile
modules/profiles/wireguard-fallback.nix  # UDP fallback (needs public IP too)
lib/helm/charts/headscale.nix           # K8s deployment chart
```

## 4. Implementation Triggers

When these conditions are met, implement in this order:

1. [ ] Static IP acquired
2. [ ] Port 443 forwarded to K8s ingress (or NodePort)
3. [ ] Port 3478/UDP opened for STUN
4. [ ] `vpn.quadtech.dev` DNS pointed to static IP
5. [ ] Deploy Headscale to `vpn` namespace via `bootstrap-refactor/`
6. [ ] Generate pre-auth keys for each machine
7. [ ] Enroll clients: `tailscale up --login-server=https://vpn.quadtech.dev`
8. [ ] Remove Tailscale SaaS auth key from SOPS

## 5. Fallback: WireGuard Native

If Headscale's DERP relay never works (no public IP), WireGuard native on backbone-01 (UDP 51820) is the fallback. It doesn't need a public IP on the server — it needs one on the *client*. But if you're behind symmetric NAT, it won't work either.

WireGuard is simpler than Headscale for a single fallback mechanism, but it's manual key management. For 2-3 machines that's fine.

---

## Open Questions (for when you have a static IP)

1. Helm chart vs raw manifests for Headscale deployment?
2. Embedded DERP or Tailscale public DERP as primary?
3. Headplane admin UI or CLI only?
4. SQLite backup strategy (Ceph S3 or host cron)?
5. OIDC auth for client enrollment or pre-auth keys only?