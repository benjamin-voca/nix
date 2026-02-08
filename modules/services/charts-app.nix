apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: charts-app
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://gitea.quadtech.dev/quadnix/helm-charts.git
    targetRevision: HEAD
    path: .
    helm:
      valueFiles:
      - values.yaml
      parameters:
      - name: argocd.nodeSelector.role
        value: backbone
      - name: gitea.nodeSelector.role
        value: backbone
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas