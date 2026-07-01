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
              # 32 GiB JVM heap (-Xms/-Xmx)
              memory: "32768M"
              # Cracked / offline accounts — do NOT authenticate against Mojang
              onlineMode: false
              gamemode: survival
              difficulty: normal
              motd: "QuadNix Create 1.21.1 (offline) — 32GB"
              # LAN exposure via MetalLB (pool 192.168.1.240-250); 192.168.1.245 is free
              serviceType: LoadBalancer
              loadBalancerIP: 192.168.1.245
              servicePort: 25565
              # Create mod + its required Modrinth dependencies (Flywheel, Ponder, ...)
              modrinth:
                projects:
                  - create
                downloadDependencies: required
              # RCON password comes from the injected minecraft-rcon-secret (sops)
              rcon:
                enabled: true
                port: 25575
                serviceType: ClusterIP
                existingSecret: minecraft-rcon-secret
                secretKey: rcon-password
            persistence:
              dataDir:
                enabled: true
                storageClass: ceph-block
                Size: 50Gi
            resources:
              requests:
                # CPU requests on backbone-01 are already ~95% saturated, so keep
                # the request low to stay schedulable; bursts use the limit below.
                cpu: 500m
                memory: 32Gi
              limits:
                cpu: 6000m
                memory: 40Gi
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
