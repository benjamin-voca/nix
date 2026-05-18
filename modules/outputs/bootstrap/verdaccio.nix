# Verdaccio bootstrap module
# Verdaccio namespace + PVC + ArgoCD Application
{
  pkgs,
  lib,
}: let
  verdaccioNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: verdaccio
      labels:
        app.kubernetes.io/name: verdaccio
  '';

  verdaccioPvc = ''
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: verdaccio-data
      namespace: verdaccio
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 10Gi
  '';

  verdaccioArgocdApp = ''
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: verdaccio
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        chart: verdaccio
        repoURL: https://charts.verdaccio.org
        targetRevision: 4.29.0
        helm:
          parameters:
          - name: service.type
            value: ClusterIP
          - name: ingress.enabled
            value: "true"
          - name: ingress.className
            value: nginx
          - name: ingress.hosts[0]
            value: verdaccio.quadtech.dev
          - name: persistence.enabled
            value: "true"
          - name: persistence.existingClaim
            value: verdaccio-data
      destination:
        server: https://kubernetes.default.svc
        namespace: verdaccio
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
  '';
in {
  chartFiles = {};

  inlineFiles = {
    "10-verdaccio-namespace.yaml" = verdaccioNamespace;
    "10a-verdaccio-pvc.yaml" = verdaccioPvc;
    "13-verdaccio-argocd-app.yaml" = verdaccioArgocdApp;
  };

  order = [
    "10-verdaccio-namespace.yaml"
    "10a-verdaccio-pvc.yaml"
    "13-verdaccio-argocd-app.yaml"
  ];
}
