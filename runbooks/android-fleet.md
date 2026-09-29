# Runbook: Android device fleet (redroid + Mullvad)

Operate the Android device fleet in namespace `android-fleet` on backbone-01: deploy changes, add devices, rotate Mullvad relays, and debug a device that isn't healthy.

## Architecture

One pod = one Android device. Each pod in the StatefulSet (`modules/outputs/bootstrap/android-fleet.nix`) runs:

- **redroid** container — full Android in a container (no KVM; needs only binderfs, built into the nixpkgs kernel). Rendering is SwiftShader software (`gpu_mode=guest`): the NVIDIA GPU is proprietary-only and unusable here.
- **vpn** sidecar (linuxserver/wireguard) — shares the pod netns; all device traffic exits through Mullvad. `AllowedIPs = 0.0.0.0/0` means a dead tunnel blackholes traffic instead of leaking the home IP.
- **initContainer** `wg-config-select` — copies `/wg-all/$HOSTNAME.conf` from k8s secret `android-fleet-wg` into an emptyDir the vpn sidecar mounts. Secret keys are `redroid-0.conf`, `redroid-1.conf`, ... mapping to sops fields `android-fleet-wg-0-conf`, `android-fleet-wg-1-conf`, ... in `secrets/roles/backbone.yaml`.
- adb is exposed per pod via a NodePort pinned by the `statefulset.kubernetes.io/pod-name` selector (redroid-0 → 30101, redroid-1 → 30102, ...).
- `/data` lives on an 8Gi ceph-block PVC per pod: installed apps and settings survive pod deletion.
- The wg0.conf in sops carries `PostUp` lines: destination rules 8990/8991 (pod subnet 10.1.19.0/24 and LAN 192.168.1.0/24 replies use `main` — without them adb/sync traffic is asymmetric and blackholes into the tunnel), tunnel-default rule 9000, wg-socket rule 9001, plus a background watchdog loop that re-adds all four every 30s and re-asserts the routes — Android's netd rewrites the routing rule table when it boots and purges foreign rules otherwise. Rule primer: 8990/8991 = local return path, 9000 = everything else → Mullvad, 9001 = wg's own fwmark'd socket → netd table 1002 (endpoint routing).
- Privileged k8s pods here run with the HOST cgroup namespace: Android's netd attaches its cgroup BPF programs at the host cgroup root. This only works because `modules/profiles/base.nix` sets `systemd.settings.Manager.DefaultIPAccounting = false` (upstream nixpkgs default-true pins systemd's sd_fw BPF programs onto every cgroup, and any other multi-attached ancestor BPF makes netd's exclusive attach fail with EPERM → netd crash-loops → Android never finishes booting).

## Deploy flow

Every change (manifests or secrets) goes through this sequence, in order:

1. Edit `modules/outputs/bootstrap/android-fleet.nix` (and/or sops secrets).
2. Render: `nix build .#bootstrap.aarch64-darwin --no-link --print-out-paths` — note the store path. Done when it prints a path.
3. `git add` every changed file — the flake only sees git-tracked files. Done when `git status` shows nothing unstaged among your changes.
4. Deploy: `nix run github:serokell/deploy-rs -- .#backbone-01 --skip-checks`. Done when output says "Deployment confirmed".
5. **Secret changes only**: the `k8s-secrets-inject` oneshot does NOT re-run on deploy. `ssh backbone01 sudo systemctl restart k8s-secrets-inject`, then confirm the secret moved: `kubectl -n android-fleet get secret android-fleet-wg -o jsonpath='{.data.redroid-0\.conf}' | base64 -d | grep Endpoint` shows the new endpoint.
6. Apply manifests: `kubectl apply -f <store-path>/28-android-fleet-namespace.yaml -f <store-path>/28a-android-fleet-statefulset.yaml -f <store-path>/28b-android-fleet-services.yaml`. Bootstrap manifests are not auto-applied by any unit.
7. If the WG config changed: `kubectl -n android-fleet delete pod redroid-0` so the initContainer copies the fresh conf. PVC keeps installed apps.

## Verify a device (run after every deploy)

All three pass = healthy:

```bash
kubectl -n android-fleet get pods                      # redroid-N 2/2 Running
kubectl -n android-fleet exec redroid-0 -c vpn -- wg show        # handshake + transfer counters growing
kubectl -n android-fleet exec redroid-0 -c vpn -- curl -s ifconfig.me  # Mullvad relay IP, never 192.168.1.*
adb connect 192.168.1.7:30101 && adb -s 192.168.1.7:30101 shell getprop sys.boot_completed  # 1
```

adb connects to the node LAN IP directly — mDNS `.local` names do not resolve for adb from the macOS host.

## Scaling up (add a device)

1. Bump `replicas` and add a matching per-pod NodePort Service (next free 3010x) in android-fleet.nix.
2. Register a Mullvad device for it — one WireGuard keypair per pod; concurrent pods sharing a key fight over the relay (key roaming). Account cap is 5 devices (includes the user's Mac); list and delete stale ones first. API flow: `POST https://api.mullvad.net/auth/v1/token` with `{"account_number": "<16 digits>"}` → bearer token; then `POST /accounts/v1/devices` with `{"pubkey": "<base64 x25519 pubkey>", "hijack_dns": false}` → returns the tunnel `ipv4_address`.
3. Write `redroid-N.conf` and add it as sops field `android-fleet-wg-N-conf` + `requiredSecrets` entry in `machines/default.nix`. Edit sops via decrypt → modify with python (pyyaml, `width=inf`) → re-encrypt to a temp file, then `sops --filename-override secrets/roles/backbone.yaml -e <temp>` — flags go BEFORE the positional arg, and `--filename-override` is required for temp files to match the creation rule.
4. Run the deploy flow above (steps 5–7 mandatory: secrets + delete pod).

### wg0.conf shape

`[Interface]` PrivateKey / `Address <tunnel-ip>/32` (IPv4 only — no v6 inside the pod) / `DNS 10.64.0.1` / `MTU 1420`; `[Peer]` relay PublicKey / `AllowedIPs 0.0.0.0/0` / `Endpoint <relay-ipv4>:51820`.

## Relay rotation

Mullvad retires relays without notice; a config pointing at a retired relay never handshakes.

1. Pick a replacement from `GET https://api.mullvad.net/www/relays/wireguard/` — filter `active: true`, take `pubkey` + `ipv4_addr_in` from the same relay entry.
2. Patch the sops conf's `PublicKey` + `Endpoint` lines (decrypt → python → re-encrypt as in scaling step 3).
3. Deploy flow steps 4–7, then run the verify checklist.

## Debug ladder

Work top-down from the symptom; each fix ends with the verify checklist.

| Symptom | Check first | Fix |
|---|---|---|
| Pod `Pending` — "unbound immediate PersistentVolumeClaims" | PVC bound yet? (`kubectl -n android-fleet get pvc`) Ceph RBD provisioning races the scheduler | Delete the pod once the PVC is Bound; StatefulSet recreates it |
| Pod `Pending` — "didn't match node affinity/selector" | nodeSelector says `kubernetes.io/hostname: backbone-01.local` — the `.local` suffix is required, the node label is not bare `backbone-01` | Fix selector in android-fleet.nix, redeploy |
| Pod `Pending` — "Insufficient cpu" | `kubectl describe node backbone-01.local` — node requests run ~97% allocated | Keep redroid `requests` tiny (100m is proven); leave `limits` at 2 CPU / 4Gi |
| `CreateContainerError`: "openat etc/passwd: path escapes from parent" | containerd version on the node (`containerd --version` via ssh) — Android images symlink `/etc -> /system/etc`, broken by containerd < 2.2.2 (containerd#13382) | The fix lives in `modules/profiles/kubernetes/containerd-registry.nix` (nixpkgs-containerd overlay, containerd 2.4.0). Redeploying it restarts containerd+kubelet → ALL pods on the node bounce briefly. Expect a cluster-wide blip |
| `sys.boot_completed` stays empty; scrcpy dies with `InputManagerGlobal.getInputDevice ... null object reference` NPE; no `input`/`settings` binder services; `system_server` zombie in `ps` | The NPE is a symptom, not a bug: the framework never finished booting. `logcat -d | grep -iE "netd|bpf"` for the real killer: netd SIGABRT-looping with "Program .../prog_netd_cgroupskb_egress_stats attach failed [Operation not permitted]" = a multi-attached ancestor BPF program (systemd IP accounting's sd_fw_*) is squatting the cgroup | Check `systemctl show -p IPAccounting` on the host: must be `no`. The fix is the `DefaultIPAccounting = false` override in `modules/profiles/base.nix`; after redeploying it, delete the pod for a clean boot |
| Tunnel dead after Android finishes booting: `wg show` transfer 0 0 / no handshake, DNS lookups exit 6 | netd rebuilt `ip rule` (10000–32000 range, `32000: unreachable`) and purged wg-quick's rules; main table has no default (netd keeps it in table 1002) | Verify rules `9000`/`9001` exist in the vpn container (`ip rule`). The wg0.conf PostUp watchdog re-adds them within 30s — if the rules are missing, the conf in the k8s secret predates the PostUp fix: re-run the secret-update deploy flow |
| adb `state=offline` or connect timeout; `netstat` in redroid shows :5555 stuck in `SYN_RECV` | Asymmetric routing: the priority-9000 tunnel rule was sending response packets (to node/pod/LAN clients) into Mullvad, so SYN-ACKs never came back | Fixed declaratively: destination rules `8990` (`to 10.1.19.0/24`) and `8991` (`to 192.168.1.0/24`) force local-subnet replies via `main` — part of the PostUp block. If missing, the k8s secret conf predates the 5-rule version |
| Device restart-loop with exit 137 after ~4 min, or kubelet kills it mid-boot | adbd listens on :5555 EARLY in boot — a `tcpSocket: 5555` probe passes instantly, so the liveness budget burns down during the slow system_server/dexopt phase and kubelet SIGKILLs the container before boot completes | Probes must exec-gate on boot state (`getprop sys.boot_completed | grep -q 1`), never tcpSocket — this is how android-fleet.nix is written; keep it that way |
| Pod Pending with "Insufficient cpu" but requests look tiny | Node allocatable is 7500m (not the 7560m `describe` implies) and requests run ~7440m+ | `kubectl get node -o jsonpath='{.status.allocatable.cpu}'` for the real number; keep redroid+vpn requests ≤ 45m total. Also: StatefulSet updates do NOT reschedule an already-Pending pod — `kubectl delete pod` after applying new requests |
| Pod Init stuck | `kubectl -n android-fleet logs redroid-0 -c wg-config-select` — usually the secret key `$HOSTNAME.conf` is missing | Add the conf for that pod to secret `android-fleet-wg` (scaling step 3) |
| `wg show` shows no handshake | Relay retired? Look up its `active` flag in the relays endpoint | Relay rotation above |
| `curl` exits 6 (couldn't resolve host) in vpn container | DNS 10.64.0.1 is Mullvad's, reachable only through the tunnel — exit 6 = tunnel down | Same: rotation / handshake debugging |
| adb shows "unable to connect" | Pod running? Service selector `statefulset.kubernetes.io/pod-name` matches? NodePort right? | `kubectl -n android-fleet get svc` and compare nodePort to the pod ordinal |

## Landmines

- **Imperative one-off fixes are debt**: every manual `kubectl` action taken to recover the fleet must land in this repo (repo rule). The runbook fixes above are the declarative homes for the ones already taken.
- `k8s-secrets-inject` is a oneshot: deploy-rs activating a new secret does nothing until you restart the unit.
- sops CLI: flags before the positional file arg; `--filename-override` for any file outside `secrets/`.
- Mullvad relays die silently; always verify `active: true` before pinning one into a config.
- Mullvad account: 5 device slots, shared with the user's personal machine. Clean up dead fleet devices before registering new ones.
- Node redeploys that touch containerd bounce every pod on backbone-01 (including kube-system) — schedule accordingly.
- **Never hostPath-mount `/sys/fs/bpf` or `/sys/fs/cgroup` into a redroid pod.** Android's init/netbpfload mount bpffs filesystems inside the pod; through a hostPath bind those mounts propagate to the host path and can stack a bpffs OVER a real host directory (this bricked `/tmp` once: deploy-rs failed because root couldn't write /tmp). Recovery: delete the pod, `sudo umount` the affected host path, redeploy. The privileged+host-cgroupns defaults already give netd everything it needs — no extra mounts required.
- The image is pinned to `15.0.0_64only-250627`: build `240905` has a broken platform↔media.swcodec apex pairing — Codec2 encoders never register (logcat: `MediaCodecList: ignored failed builder` after the OmxInfoBuilder line, plus `missing struct descriptor #Param::CoreIndex` spam from mediaswcodec) and scrcpy dies with `Could not create default video encoder for h264`. On 250627 the healthy signature is `Codec2Client: Available Codec2 services: "software"`; one `ignored failed builder` for the OMX path is normal (redroid has no IOmxStore). Note both builds' netd BPF boot-loop was a HOST problem (systemd DefaultIPAccounting squatting, fixed in `modules/profiles/base.nix`) — if you bump the pin again, verify a full boot (`sys.boot_completed=1` + handshake + scrcpy encoders) before trusting it.
