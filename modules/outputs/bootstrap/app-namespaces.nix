# App namespaces bootstrap module
# Namespaces + ArgoCD Applications for EduKurs, BatllavaTourist
{
  pkgs,
  lib,
}: let
  d = import ../../../lib/domain.nix;
  edukursNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: edukurs
      labels:
        app.kubernetes.io/name: edukurs
  '';

  batllavatouristNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: batllavatourist
      labels:
        app.kubernetes.io/name: batllavatourist
  '';


  edukursArgocdApp = ''
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: edukurs
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: ${d.url "forge"}/QuadCoreTech/edukurs.git
        path: k8s
        targetRevision: main
      destination:
        server: https://kubernetes.default.svc
        namespace: edukurs
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
  '';

  batllavatouristArgocdApp = ''
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: batllavatourist
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: ${d.url "forge"}/QuadCoreTech/batllavatourist.git
        path: k8s
        targetRevision: main
      destination:
        server: https://kubernetes.default.svc
        namespace: batllavatourist
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
  '';


in {
  chartFiles = {};

  inlineFiles = {
    "15-edukurs-namespace.yaml" = edukursNamespace;
    "15-batllavatourist-namespace.yaml" = batllavatouristNamespace;
    "16-edukurs-argocd-app.yaml" = edukursArgocdApp;
    "16-batllavatourist-argocd-app.yaml" = batllavatouristArgocdApp;
  };

  order = [
    "15-edukurs-namespace.yaml"
    "15-batllavatourist-namespace.yaml"
    "16-edukurs-argocd-app.yaml"
    "16-batllavatourist-argocd-app.yaml"
  ];
}
