# Monitoring bootstrap module
# Prometheus + Grafana charts, namespaces, secrets, ingress
{
  pkgs,
  lib,
  existingCharts,
}: let
  monitoringChart = existingCharts.prometheus;
  grafanaChart = existingCharts.grafana;

  monitoringNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: monitoring
      labels:
        app.kubernetes.io/name: monitoring
    ---
    apiVersion: v1
    kind: Namespace
    metadata:
      name: grafana
      labels:
        app.kubernetes.io/name: grafana
  '';

  grafanaDbSecret = ''
    apiVersion: v1
    kind: Secret
    metadata:
      name: grafana-db
      namespace: grafana
    type: Opaque
    stringData:
      GF_DATABASE_TYPE: postgres
      GF_DATABASE_HOST: shared-pg-rw.cnpg-system.svc.cluster.local:5432
      GF_DATABASE_NAME: grafana
      GF_DATABASE_USER: edukurs
      GF_DATABASE_PASSWORD: PLACEHOLDER
      GF_SECURITY_ADMIN_PASSWORD: PLACEHOLDER
  '';

  grafanaIngress = ''
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: grafana
      namespace: grafana
      annotations:
        nginx.ingress.kubernetes.io/ssl-redirect: "false"
        nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    spec:
      ingressClassName: nginx
      rules:
      - host: grafana.quadtech.dev
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 80
  '';
in {
  chartFiles = {
    "12-monitoring-chart.yaml" = monitoringChart;
    "12-grafana-chart.yaml" = grafanaChart;
  };

  inlineFiles = {
    "11-monitoring-namespace.yaml" = monitoringNamespace;
    "12-grafana-db-secret.yaml" = grafanaDbSecret;
    "12a-grafana-ingress.yaml" = grafanaIngress;
  };

  # Monitoring chart needs annotation stripping
  needsAnnotationStrip = ["12-monitoring-chart.yaml"];

  order = [
    "11-monitoring-namespace.yaml"
    "12-monitoring-chart.yaml"
    "12-grafana-db-secret.yaml"
    "12-grafana-chart.yaml"
    "12a-grafana-ingress.yaml"
  ];
}
