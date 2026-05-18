# Minecraft bootstrap module
# Minecraft namespace + ArgoCD Application
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
        targetRevision: 5.1.1
        helm:
          valueFiles:
          - values.yaml
          values: |
            minecraftServer:
              eula: "TRUE"
              version: "1.21.4"
              gamemode: survival
              difficulty: normal
              allow-flight: true
              enable-rcon: true
              rcon.password: "PLACEHOLDER"
              rcon.port: 25575
              query.enabled: true
              query.port: 25565
            persistence:
              enabled: true
              storageClass: ceph-block
              size: 20Gi
            service:
              type: LoadBalancer
              loadBalancerIP: 192.168.1.245
            ingress:
              enabled: true
              ingressClassName: nginx
              annotations:
                nginx.ingress.kubernetes.io/ssl-redirect: "false"
                nginx.ingress.kubernetes.io/proxy-body-size: "50m"
              hosts:
                - minecraft.quadtech.dev
              tls:
                - secretName: minecraft-tls
                  hosts:
                    - minecraft.quadtech.dev
            resources:
              requests:
                cpu: 500m
                memory: 2Gi
              limits:
                cpu: 4000m
                memory: 6Gi
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
