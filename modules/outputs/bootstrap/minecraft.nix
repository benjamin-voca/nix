# Minecraft bootstrap module
# Minecraft namespace + ArgoCD Application
#
# Server profile:
#   - Minecraft 1.21.1 on NeoForge (required by Create 6.x)
#   - Create mod (+ required deps) installed via Modrinth
#   - online-mode OFF (cracked / offline accounts)
#   - 32 GiB JVM heap (MEMORY=32768M), 40Gi container limit
#   - RCON enabled via the injected `minecraft-rcon-secret`
#   - Exposed as a MetalLB LoadBalancer on 192.168.1.245:25565 (LAN VIP)
#
# NOTE on chart value keys (itzg/minecraft-server-charts):
#   The main Service type/IP live under `minecraftServer.serviceType` and
#   `minecraftServer.loadBalancerIP` — NOT under a top-level `service:` block.
#   Persistence lives under `persistence.dataDir.{enabled,storageClass,Size}` —
#   NOT under `persistence.enabled/size`.  Using the wrong keys silently falls
#   back to chart defaults (ClusterIP service, no PVC, default 1G memory).
{
  pkgs,
  lib,
}: let
  minecraftNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: minecraft
      labels:
        app.kubernetes.io/name: minecraft
  '';

  minecraftArgocdApp = ''
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: minecraft
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        chart: minecraft
        repoURL: https://itzg.github.io/minecraft-server-charts
        targetRevision: 5.1.3
        helm:
          values: |
            minecraftServer:
              eula: "TRUE"
              # NeoForge is the only loader Create 6.x ships for on 1.21.1
              type: NEOFORGE
              version: "1.21.1"
              # Heap 12 GiB + Aikar's G1 flags. Counter-intuitive but more RAM =
              # MORE lag in Minecraft: GC pauses scale with heap size, and default
              # G1GC on 32 GiB caused multi-second stalls ("Can't keep up", chunks
              # refusing to generate). If you ever want a big heap again, use ZGC
              # (-XX:+UseZGC) instead of G1 rather than just raising this number.
              memory: "12288M"
              jvmXXOpts: "-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1RSetStatsPausePeriodTicks=99 -XX:+PerfDisableSharedMem"
              # Lower view/sim distance to cut chunk-gen + entity-tick CPU load
              viewDistance: 7
              # Cracked / offline accounts — do NOT authenticate against Mojang
              onlineMode: false
              gamemode: survival
              difficulty: normal
              motd: "QuadNix Create 1.21.1 (offline)"
              # LAN exposure via MetalLB (pool 192.168.1.240-250); 192.168.1.245 is free
              serviceType: LoadBalancer
              loadBalancerIP: 192.168.1.245
              servicePort: 25565
              # Create mod + its required Modrinth dependencies (Flywheel, Ponder, ...)
              # JEI = recipe/item browser ("Just Enough Items"); pairs with Create.
              # teleport-commands = server-side teleport commands for all players
              #   (vanilla /tp needs op-lvl2 which also grants /give etc.; this
              #   avoids handing out cheats). Client-unsupported = no client mod.
              # sophisticated-backpacks = backpacks (auto-pulls sophisticated-core).
              # allowedVersionType: beta — JEI's 1.21.1/NeoForge builds are all beta.
              modrinth:
                projects:
                  - create
                  - jei
                  - teleport-commands
                  - sophisticated-backpacks
                downloadDependencies: required
                allowedVersionType: beta
              # RCON password comes from the injected minecraft-rcon-secret (sops)
              rcon:
                enabled: true
                port: 25575
                serviceType: ClusterIP
                existingSecret: minecraft-rcon-secret
                secretKey: rcon-password
            extraEnv:
              # Fewer simulated chunks = big per-tick CPU win (chart has no
              # dedicated simulationDistance key, so pass the itzg env directly).
              SIMULATION_DISTANCE: "6"
            persistence:
              dataDir:
                enabled: true
                storageClass: ceph-block
                Size: 200Gi
            resources:
              requests:
                # CPU requests on backbone-01 are already ~95% saturated, so keep
                # the request low to stay schedulable; bursts use the limit below.
                cpu: 500m
                memory: 14Gi
              limits:
                cpu: 6000m
                memory: 18Gi
      destination:
        server: https://kubernetes.default.svc
        namespace: minecraft
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
  '';
in {
  chartFiles = {};

  inlineFiles = {
    "11-minecraft-namespace.yaml" = minecraftNamespace;
    "14-minecraft-argocd-app.yaml" = minecraftArgocdApp;
  };

  order = [
    "11-minecraft-namespace.yaml"
    "14-minecraft-argocd-app.yaml"
  ];
}
