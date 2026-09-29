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
              # Android 14, NOT 15: both 15.0.0 redroid builds (240905 and
              # 250627) ship a broken platform<->media.swcodec apex pairing —
              # Codec2 param-descriptor negotiation fails ("missing struct
              # descriptor #Param::CoreIndex" spam), NO encoders register, and
              # scrcpy dies with NAME_NOT_FOUND. The 14 image pairing is
              # consistent. See runbooks/android-fleet.md.
              image: redroid/redroid:14.0.0_64only-latest
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
                failureThreshold: 90
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
          volumes:
            - name: wg-all
              secret:
                secretName: android-fleet-wg
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
