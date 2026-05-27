# ArgoCD bootstrap module
# ArgoCD namespace + chart + forgejo repo credentials
{
  pkgs,
  lib,
  charts,
  kubelib,
}: let
  argocdChart =
    pkgs.lib.pipe
    {
      name = "argocd";
      chart = charts.argoproj.argo-cd;
      namespace = "argocd";
      values =
        (import ../../../lib/argocd-values.nix {
          domain = "argocd.quadtech.dev";
          serverUrl = "http://argocd.quadtech.dev";
          serverReplicas = 1;
          controllerReplicas = 1;
          repoServerReplicas = 1;
          enableApplicationSet = true;
          enableNotifications = true;
        })
        // {
          configs = {
            cm = {
              "server.insecure" = true;
              "server.forceHttp" = true;
              url = "http://argocd.quadtech.dev";
            };
            params = {
              "server.insecure" = true;
              "server.forceHttp" = true;
            };
          };
        };
    }
    [kubelib.buildHelmChart];

  argocdNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: argocd
      labels:
        app.kubernetes.io/name: argocd
  '';

  argocdForgejoRepo = ''
    apiVersion: v1
    kind: Secret
    metadata:
      name: forgejo-quadtech-repo-creds
      namespace: argocd
      labels:
        argocd.argoproj.io/secret-type: repo-creds
    type: Opaque
    stringData:
      url: https://forge.quadtech.dev/QuadCoreTech
      username: PLACEHOLDER
      password: PLACEHOLDER
  '';

  argocdIngress = ''
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: argocd-server
      namespace: argocd
      annotations:
        nginx.ingress.kubernetes.io/proxy-body-size: "512m"
    spec:
      ingressClassName: nginx
      rules:
      - host: argocd.quadtech.dev
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
  '';
in {
  chartFiles = {
    "01b-argocd.yaml" = argocdChart;
  };

  inlineFiles = {
    "01a-argocd-namespace.yaml" = argocdNamespace;
    "04-argocd-forgejo-repo.yaml" = argocdForgejoRepo;
    "01c-argocd-ingress.yaml" = argocdIngress;
  };

  # ArgoCD chart needs annotation stripping
  needsAnnotationStrip = ["01b-argocd.yaml"];

  order = ["01a-argocd-namespace.yaml" "01b-argocd.yaml" "01c-argocd-ingress.yaml"];
}
