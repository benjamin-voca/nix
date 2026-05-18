# Harbor bootstrap module
# Harbor namespace + chart + PVCs + ingress
{
  pkgs,
  lib,
  existingCharts,
}: let
  harborChart = existingCharts.harbor;

  harborNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: harbor
      labels:
        app.kubernetes.io/name: harbor
  '';

  harborPvcs = ''
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: harbor-registry-ceph
      namespace: harbor
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 100Gi
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: harbor-jobservice-ceph
      namespace: harbor
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 1Gi
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: harbor-database-ceph
      namespace: harbor
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 1Gi
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: harbor-redis-ceph
      namespace: harbor
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 1Gi
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: harbor-trivy-ceph
      namespace: harbor
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ceph-block
      resources:
        requests:
          storage: 5Gi
  '';

  harborIngress = ''
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: harbor-ingress
      namespace: harbor
      annotations:
        nginx.ingress.kubernetes.io/proxy-body-size: "0"
        nginx.ingress.kubernetes.io/ssl-redirect: "false"
        nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
        nginx.ingress.kubernetes.io/proxy-buffering: "off"
    spec:
      ingressClassName: nginx
      tls:
      - hosts:
        - harbor.quadtech.dev
        secretName: harbor-ingress
      rules:
      - host: harbor.quadtech.dev
        http:
          paths:
          - path: /api/
            pathType: Prefix
            backend:
              service:
                name: harbor-core
                port:
                  number: 80
          - path: /service/
            pathType: Prefix
            backend:
              service:
                name: harbor-core
                port:
                  number: 80
          - path: /v2/
            pathType: Prefix
            backend:
              service:
                name: harbor-core
                port:
                  number: 80
          - path: /c/
            pathType: Prefix
            backend:
              service:
                name: harbor-core
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: harbor-portal
                port:
                  number: 80
  '';
in {
  chartFiles = {
    "11-harbor-chart.yaml" = harborChart;
  };

  inlineFiles = {
    "09-harbor-namespace.yaml" = harborNamespace;
    "09a-harbor-pvcs-ceph.yaml" = harborPvcs;
    "12-harbor-ingress.yaml" = harborIngress;
  };

  order = [
    "09-harbor-namespace.yaml"
    "09a-harbor-pvcs-ceph.yaml"
    "11-harbor-chart.yaml"
    "12-harbor-ingress.yaml"
  ];
}
