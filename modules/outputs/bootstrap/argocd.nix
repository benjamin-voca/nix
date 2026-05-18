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
          imageTag = "v2.9.3";
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
    apiVersion: argoproj.io/v1alpha1
    kind: Repository
    metadata:
      name: forgejo-quadtech
      namespace: argocd
    spec:
      type: git
      url: https://forge.quadtech.dev/QuadCoreTech
      usernameSecret:
        name: argocd-forgejo-creds
        key: username
      passwordSecret:
        name: argocd-forgejo-creds
        key: password
  '';
in {
  chartFiles = {
    "01b-argocd.yaml" = argocdChart;
  };

  inlineFiles = {
    "01a-argocd-namespace.yaml" = argocdNamespace;
    "04-argocd-forgejo-repo.yaml" = argocdForgejoRepo;
  };

  # ArgoCD chart needs annotation stripping
  needsAnnotationStrip = ["01b-argocd.yaml"];

  order = ["01a-argocd-namespace.yaml" "01b-argocd.yaml"];
}
