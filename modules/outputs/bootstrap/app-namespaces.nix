# App namespaces bootstrap module
# Namespaces + ArgoCD Applications for EduKurs, BatllavaTourist, QuadPacienti
{
  pkgs,
  lib,
}: let
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

  quadpacientiNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: quadpacienti
      labels:
        app.kubernetes.io/name: quadpacienti
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
        repoURL: https://forge.quadtech.dev/QuadCoreTech/edukurs.git
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
        repoURL: https://forge.quadtech.dev/QuadCoreTech/batllavatourist.git
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

  quadpacientiArgocdApp = ''
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: quadpacienti
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: https://forge.quadtech.dev/QuadCoreTech/quadpacienti.git
        path: k8s
        targetRevision: main
      destination:
        server: https://kubernetes.default.svc
        namespace: quadpacienti
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
    "15-quadpacienti-namespace.yaml" = quadpacientiNamespace;
    "16-edukurs-argocd-app.yaml" = edukursArgocdApp;
    "16-batllavatourist-argocd-app.yaml" = batllavatouristArgocdApp;
    "16-quadpacienti-argocd-app.yaml" = quadpacientiArgocdApp;
  };

  order = [
    "15-edukurs-namespace.yaml"
    "15-batllavatourist-namespace.yaml"
    "15-quadpacienti-namespace.yaml"
    "16-edukurs-argocd-app.yaml"
    "16-batllavatourist-argocd-app.yaml"
    "16-quadpacienti-argocd-app.yaml"
  ];
}
