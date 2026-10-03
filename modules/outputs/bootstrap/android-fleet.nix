# Android device fleet bootstrap module
# Namespace + StatefulSet (redroid) + per-device adb Services
#
# Architecture:
#   - Each pod = one Android device (redroid: full Android in a container,
#     no KVM/emulator needed — requires only binderfs, which the nixpkgs
#     kernel ships built-in for kernel >= 5.0).
#   - A WireGuard sidecar shares the pod network namespace and is brought up
#     with wg0.conf (from the injected `android-fleet-wg` sops secret).
#     wg-quick policy routing + `AllowedIPs = 0.0.0.0/0` force ALL pod
#     traffic through the tunnel; if the tunnel dies, traffic blackholes
#     instead of leaking out the node IP.
#   - GPU: redroid cannot use proprietary NVIDIA GL, so rendering is
#     SwiftShader (software, `gpu_mode=guest`). The NVIDIA card sits idle.
#
# Ops:
#   - adb:    adb connect backbone01.local:30101   (30102, 30103, ... per device)
#   - screen: scrcpy -s backbone01.local:30101
#   - VPN:    kubectl -n android-fleet exec redroid-0 -c vpn -- wg show
#   - Scale:  bump `replicas` AND add a matching per-pod NodePort Service
#     below (pod-name selector + a free nodePort).
{
  pkgs,
  lib,
}: let
  # image = "redroid/redroid:14.0.0_64only-latest";
  androidNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: android-fleet
      labels:
        app.kubernetes.io/name: android-fleet
  '';

  # One pod = one Android device. VPN sidecar owns the shared netns.
  androidStatefulSet = ''
    apiVersion: apps/v1
    kind: StatefulSet
    metadata:
      name: redroid
      namespace: android-fleet
      labels:
        app.kubernetes.io/name: redroid
    spec:
      replicas: 1
      serviceName: redroid-headless
      selector:
        matchLabels:
          app.kubernetes.io/name: redroid
      template:
        metadata:
          labels:
            app.kubernetes.io/name: redroid
        spec:
          # Single-node cluster: everything runs on backbone-01
          nodeSelector:
            kubernetes.io/hostname: backbone-01.local
          tolerations:
            - key: role
              operator: Equal
              value: backbone
              effect: NoSchedule
            - key: infra
              operator: Equal
              value: "true"
              effect: NoSchedule
          terminationGracePeriodSeconds: 60
          # Grab this pod's WireGuard config (secret holds one conf per
          # device, keyed by pod name) and publish it as wg0.conf
          initContainers:
            - name: wg-config-select
              image: busybox:stable
              command: ["sh", "-c", "cp /wg-all/''${HOSTNAME}.conf /wg-config/wg0.conf"]
              volumeMounts:
                - name: wg-all
                  mountPath: /wg-all
                  readOnly: true
                - name: wg-config
                  mountPath: /wg-config
            # Stage a STATIC busybox for the redroid entrypoint wrapper:
            # pre-init the redroid rootfs cannot exec any /system/bin binary
            # (their ELF interpreter lives in /apex, which init mounts later).
            # Alpine's /bin/busybox has full applets but is dynamically linked
            # against musl (the redroid rootfs has no loader) — stage the musl
            # loader alongside and invoke busybox THROUGH it.
            - name: stage-wrapper
              image: alpine:3.20
              command: ["sh", "-c", "cp /bin/busybox /lib/ld-musl-x86_64.so.1 /wrapper/ && chmod 755 /wrapper/busybox /wrapper/ld-musl-x86_64.so.1"]
              volumeMounts:
                - name: wrapper
                  mountPath: /wrapper
          containers:
            # ── VPN sidecar: all pod traffic (including Android's) exits here ──
            - name: vpn
              image: lscr.io/linuxserver/wireguard:latest
              securityContext:
                privileged: true
              volumeMounts:
                - name: wg-config
                  mountPath: /config/wg0.conf
                  subPath: wg0.conf
                  readOnly: true
              resources:
                requests:
                  cpu: 5m
                  memory: 64Mi
                limits:
                  cpu: 200m
                  memory: 128Mi
            # ── The Android device ──
            # redroid needs containerd >= 2.2.2 on the node (see
            # profiles/kubernetes/containerd-registry.nix overlay)
            - name: redroid
              # Android 15 build 250627. The historical "no encoders" failure
              # was NOT an image bug — the host kernel lacked DMA-BUF heaps
              # (fixed via boot.kernelPatches in machines/default.nix; see
              # runbooks/android-fleet.md). 14 was a detour: its init
              # crash-loops in this pod environment, while 15 boots.
              image: redroid/redroid:14.0.0_64only-latest
              # Android init must mount cgroup2 ITSELF (libprocessgroup
              # SetupCgroups); cgroup2 is single-instance per mount ns, so the
              # CRI-injected /sys/fs/cgroup mount makes init's own mount EBUSY
              # ("Failed to setup cgroup2 cgroup" → full self-shutdown).
              # Wrapper: detach the CRI mount, mount a fresh cgroup2 with the
              # options init wants, then hand over. Needs cgroupns=private
              # (fresh superblock accepts the data) — set in
              # profiles/kubernetes/containerd-registry.nix.
              command:
                - /wrapper/ld-musl-x86_64.so.1
                - /wrapper/busybox
                - sh
                - -c
                # Every busybox call needs the loader prefix — its PT_INTERP
                # (/lib/ld-musl-x86_64.so.1) does not exist in the redroid
                # rootfs, so direct exec ENOENTs. "$@" re-passes the
                # --androidboot.* bootargs (they arrive as sh positionals
                # since command+args concatenate).
                - /wrapper/ld-musl-x86_64.so.1 /wrapper/busybox umount -l /sys/fs/cgroup; exec /init "$@"  # NO remount: cgroup2 is single-instance per mount ns — init must mount it itself (as in the working ctr boots)
              securityContext:
                privileged: true
              args:
                - --androidboot.redroid_width=720
                - --androidboot.redroid_height=1280
                - --androidboot.redroid_dpi=320
                # NVIDIA proprietary GL is unusable by redroid — SwiftShader it is
                - --androidboot.redroid_gpu_mode=guest
              ports:
                - name: adb
                  containerPort: 5555
              # Probes use sys.boot_completed, NOT tcp: adbd listens EARLY in
              # boot, so tcp probes "pass" immediately, the startup budget
              # evaporates, and liveness SIGKILLs the container mid-boot-storm
              # when adbd stalls under system_server/dexopt (exit 137 loop).
              startupProbe:
                exec:
                  command: ["sh", "-c", "getprop sys.boot_completed | grep -q 1"]
                periodSeconds: 10
                # kubelet default is 1s: getprop via sh exceeds it under the
                # boot-time load storm, so Ready never flips. Give it room.
                timeoutSeconds: 5
                # 16h budget: boot needs 5-6h+ per life under node CPU contention (ladder 15m..8h all consumed)
                # boots can exceed 30 min; work persists on /data so one
                # uninterrupted boot breaks the cycle
                failureThreshold: 5760
              livenessProbe:
                exec:
                  command: ["sh", "-c", "getprop sys.boot_completed | grep -q 1"]
                periodSeconds: 60
                timeoutSeconds: 10
                failureThreshold: 10
              resources:
                # backbone-01 CPU requests are ~97% allocated: request small,
                # burst to the limit when Android actually needs it.
                requests:
                  # Node CPU requests hover at ~99%: keep this small enough to
                  # schedule (50m redroid + 10m vpn). Limits still allow 2 CPU.
                  cpu: 40m
                  memory: 2Gi
                limits:
                  cpu: "2"
                  memory: 4Gi
              volumeMounts:
                - name: data
                  mountPath: /data
                - name: wrapper
                  mountPath: /wrapper
                  readOnly: true
          volumes:
            - name: wg-all
              secret:
                secretName: android-fleet-wg
            - name: wrapper
              emptyDir: {}
            - name: wg-config
              emptyDir:
                medium: Memory
      volumeClaimTemplates:
        - metadata:
            name: data
          spec:
            accessModes: ["ReadWriteOnce"]
            storageClassName: ceph-block
            resources:
              requests:
                storage: 8Gi
  '';

  # Headless service for StatefulSet DNS identities (redroid-0.redroid-headless)
  androidHeadlessService = ''
    apiVersion: v1
    kind: Service
    metadata:
      name: redroid-headless
      namespace: android-fleet
      labels:
        app.kubernetes.io/name: redroid
    spec:
      clusterIP: None
      selector:
        app.kubernetes.io/name: redroid
      ports:
        - name: adb
          port: 5555
          targetPort: adb
  '';

  # Per-device adb exposure on the LAN via NodePort on backbone-01.
  # pod-name label selector pins each Service to exactly one pod.
  # When scaling the StatefulSet, add a matching Service with a free nodePort.
  androidDeviceServices = ''
    apiVersion: v1
    kind: Service
    metadata:
      name: redroid-0-adb
      namespace: android-fleet
      labels:
        app.kubernetes.io/name: redroid
    spec:
      type: NodePort
      selector:
        app.kubernetes.io/name: redroid
        statefulset.kubernetes.io/pod-name: redroid-0
      ports:
        - name: adb
          port: 5555
          targetPort: adb
          nodePort: 30101
  '';
in {
  chartFiles = {};

  inlineFiles = {
    "28-android-fleet-namespace.yaml" = androidNamespace;
    "28a-android-fleet-statefulset.yaml" = androidStatefulSet;
    "28b-android-fleet-services.yaml" = androidHeadlessService + "\n---\n" + androidDeviceServices;
  };

  order = [
    "28-android-fleet-namespace.yaml"
    "28a-android-fleet-statefulset.yaml"
    "28b-android-fleet-services.yaml"
  ];
}
