# ArgoCD bootstrap module
# ArgoCD namespace + chart + forgejo repo credentials
{
  pkgs,
  lib,
  charts,
  kubelib,
}: let
  d = import ../../../lib/domain.nix;
  argocdChart =
    pkgs.lib.pipe
    {
      name = "argocd";
      chart = charts.argoproj.argo-cd;
      namespace = "argocd";
      values =
        (import ../../../lib/argocd-values.nix {
          domain = d.host "argocd";
          serverUrl = "http://${d.host "argocd"}";
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
              url = "http://${d.host "argocd"}";
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
      - host: ${d.host "argocd"}
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
    "01c-argocd-ingress.yaml" = argocdIngress;
  };

  # ArgoCD chart needs annotation stripping
  needsAnnotationStrip = ["01b-argocd.yaml"];

  order = ["01a-argocd-namespace.yaml" "01b-argocd.yaml" "01c-argocd-ingress.yaml"];
}
