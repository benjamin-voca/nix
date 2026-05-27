# Monitoring bootstrap module
# Prometheus + Grafana charts, namespaces, secrets, ingress + DORA scrape configs
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
    ---
    apiVersion: v1
    kind: Namespace
    metadata:
      name: loki
      labels:
        app.kubernetes.io/name: loki
  '';

  # ── Prometheus scrape configs for ArgoCD and DORA exporter ──────────────────
  # ArgoCD server exposes a /metrics endpoint on port 8082 (argocd-server-metrics).
  # The DORA exporter exposes /metrics on port 8080 in the dora namespace.
  # These static scrape targets are added via prometheus.additionalScrapeConfigs
  # in the kube-prometheus-stack values.
  doraScrapeConfigMap = ''
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: prometheus-dora-scrape-config
      namespace: monitoring
      labels:
        app.kubernetes.io/name: prometheus
    data:
      dora-scrape.yaml: |
        # Additional Prometheus scrape configs for DORA metrics
        # ArgoCD server exposes metrics at :8082/metrics
        - job_name: argocd
          scrape_interval: 60s
          scrape_timeout: 30s
          static_configs:
            - targets:
                - argocd-server.argocd:8082
          relabel_configs:
            - source_labels: [__address__]
              target_label: instance
        # DORA exporter at dora-exporter.dora:8080/metrics
        - job_name: dora-exporter
          scrape_interval: 60s
          scrape_timeout: 30s
          static_configs:
            - targets:
                - dora-exporter.dora:8080
          relabel_configs:
            - source_labels: [__address__]
              regex: dora-exporter\..+:8080
              replacement: dora
              target_label: app
  '';

  orkestrGrafanaDashboard = ''
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: grafana-dashboard-orkestr-k8s
      namespace: grafana
      labels:
        grafana_dashboard: "1"
    data:
      orkestr-k8s.json: |-
        {
          "title": "Orkestr K8s Overview",
          "uid": "orkestr-k8s-overview",
          "schemaVersion": 38,
          "version": 1,
          "refresh": "30s",
          "timezone": "browser",
          "tags": ["orkestr", "kubernetes"],
          "templating": {
            "list": [
              {
                "name": "namespace",
                "type": "query",
                "datasource": "Prometheus",
                "query": "label_values(kube_pod_info, namespace)",
                "current": {"text": "orkestr", "value": "orkestr"}
              },
              {
                "name": "pod",
                "type": "query",
                "datasource": "Prometheus",
                "query": "label_values(kube_pod_info{namespace=\"$namespace\"}, pod)",
                "includeAll": true,
                "multi": true
              }
            ]
          },
          "panels": [
            {
              "type": "timeseries",
              "title": "Pod CPU (cores)",
              "datasource": "Prometheus",
              "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
              "targets": [
                {
                  "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"$namespace\", pod=~\"$pod\", container!=\"\", image!=\"\"}[5m])) by (pod)",
                  "legendFormat": "{{pod}}"
                }
              ]
            },
            {
              "type": "timeseries",
              "title": "Pod Memory (MiB)",
              "datasource": "Prometheus",
              "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
              "targets": [
                {
                  "expr": "sum(container_memory_working_set_bytes{namespace=\"$namespace\", pod=~\"$pod\", container!=\"\", image!=\"\"}) by (pod) / 1024 / 1024",
                  "legendFormat": "{{pod}}"
                }
              ]
            },
            {
              "type": "stat",
              "title": "Pod Restarts (last 24h)",
              "datasource": "Prometheus",
              "gridPos": {"h": 6, "w": 8, "x": 0, "y": 8},
              "targets": [
                {
                  "expr": "sum(increase(kube_pod_container_status_restarts_total{namespace=\"$namespace\", pod=~\"$pod\"}[24h]))",
                  "legendFormat": "restarts"
                }
              ]
            },
            {
              "type": "stat",
              "title": "Ready Pods",
              "datasource": "Prometheus",
              "gridPos": {"h": 6, "w": 8, "x": 8, "y": 8},
              "targets": [
                {
                  "expr": "sum(kube_pod_status_ready{namespace=\"$namespace\", condition=\"true\", pod=~\"$pod\"})",
                  "legendFormat": "ready"
                }
              ]
            },
            {
              "type": "stat",
              "title": "Running Pods",
              "datasource": "Prometheus",
              "gridPos": {"h": 6, "w": 8, "x": 16, "y": 8},
              "targets": [
                {
                  "expr": "sum(kube_pod_status_phase{namespace=\"$namespace\", phase=\"Running\", pod=~\"$pod\"})",
                  "legendFormat": "running"
                }
              ]
            },
            {
              "type": "logs",
              "title": "Orkestr Logs",
              "datasource": "Loki",
              "gridPos": {"h": 12, "w": 24, "x": 0, "y": 14},
              "targets": [
                {
                  "expr": "{namespace=\"$namespace\"}"
                }
              ]
            }
          ]
        }
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
    "12b-loki-chart.yaml" = existingCharts.loki;
    "12c-promtail-chart.yaml" = existingCharts.promtail;
  };

  inlineFiles = {
    "11-monitoring-namespace.yaml"         = monitoringNamespace;
    "12a-grafana-ingress.yaml"             = grafanaIngress;
    "12d-orkestr-dashboard.yaml"           = orkestrGrafanaDashboard;
  };

  # Monitoring chart needs annotation stripping
  needsAnnotationStrip = ["12-monitoring-chart.yaml"];

  order = [
    "11-monitoring-namespace.yaml"
    "12-monitoring-chart.yaml"
    "12-grafana-chart.yaml"
    "12a-grafana-ingress.yaml"
    "12b-loki-chart.yaml"
    "12c-promtail-chart.yaml"
    "12d-orkestr-dashboard.yaml"
  ];
}