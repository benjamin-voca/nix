# DORA Metrics Bootstrap Module
# DORA namespace + metrics exporter deployment + service + Grafana dashboard
{
  lib,
  pkgs,
}: let
  # ── Namespace ────────────────────────────────────────────────────────────────
  doraNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: dora
      labels:
        app.kubernetes.io/name: dora
  '';

  # ── DORA Exporter ConfigMap ─────────────────────────────────────────────────
  # The exporter script queries:
  #   - ArgoCD API (argocd-server.argocd:80) for sync history
  #   - Forgejo API (forgejo-http.forgejo:3000) for commit history
  # and exposes Prometheus gauge/counter metrics at /metrics
  doraExporterConfigMap = let
    exporterScript = pkgs.writeScript "dora-exporter.py" ''
    #!/usr/bin/env python3
    """
    DORA Metrics Exporter for Orkestr.
    Queries ArgoCD and Forgejo APIs to compute:
      - Deployment Frequency
      - Lead Time for Changes
      - Change Failure Rate
      - Mean Time to Recovery
    Exposes Prometheus gauge metrics at /metrics.
    """
    import http.server
    import json
    import os
    import re
    import threading
    import time
    import urllib.request
    from urllib.error import HTTPError, URLError

    # ── Configuration ──────────────────────────────────────────────────────────
    ARGO_URL      = os.getenv("ARGO_URL",      "http://argocd-server.argocd:80")
    ARGO_TOKEN    = os.getenv("ARGO_TOKEN",     "")
    FORGEJO_URL   = os.getenv("FORGEJO_URL",   "http://forgejo-http.forgejo:3000")
    FORGEJO_TOKEN = os.getenv("FORGEJO_TOKEN", "")
    APPS          = os.getenv("APPS",         "orkestr").split(",")
    REPO          = os.getenv("REPO",          "QuadCoreTech/orkestr")
    METRICS_PORT  = int(os.getenv("METRICS_PORT", "8080"))
    INTERVAL      = int(os.getenv("INTERVAL",  "300"))   # seconds between scrapes

    HEADERS_ARGO = {"Authorization": f"Bearer {ARGO_TOKEN}"} if ARGO_TOKEN else {}
    HEADERS_FG   = {"Authorization": f"token {FORGO_TOKEN}"} if FORGEJO_TOKEN else {}

    # ── State ───────────────────────────────────────────────────────────────────
    metrics = {}
    metrics_lock = threading.Lock()

    def fetch_json(url, headers=None):
        req = urllib.request.Request(url, headers=headers or {})
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())

    def app_history(app):
        """Return list of ArgoCD sync history entries {id, started, phase, source}."""
        try:
            data = fetch_json(f"{ARGO_URL}/api/v1/applications/{app}/history",
                              headers=HEADERS_ARGO)
            return data.get("items", [])
        except Exception:
            return []

    def app_history_id(app, id_):
        """Return detailed history entry including the deployed commit SHA."""
        try:
            data = fetch_json(f"{ARGO_URL}/api/v1/applications/{app}/history/{id_}",
                              headers=HEADERS_ARGO)
            return data
        except Exception:
            return {}

    def deployments_30d(app):
        """Return list of {ts, sha, succeeded} for last 30 days of ArgoCD syncs."""
        history = app_history(app)
        cutoff = time.time() - 30 * 86400
        deploys = []
        for entry in reversed(history):
            # 'startedAt' is ISO 8601
            started = entry.get("startedAt", "")
            try:
                ts = time.mktime(time.strptime(started, "%Y-%m-%dT%H:%M:%SZ"))
            except Exception:
                continue
            if ts < cutoff:
                break
            phase = entry.get("phase", "")
            succeeded = phase in ("Succeeded", "Synced")
            deploys.append({"ts": ts, "succeeded": succeeded})
        return deploys

    def lead_time(app):
        """Compute lead time: median hours from first commit in a deploy to deploy time.
        Returns (median_hours, sample_count).
        """
        history = app_history(app)
        cutoff = time.time() - 30 * 86400
        lead_times = []

        for entry in reversed(history):
            started = entry.get("startedAt", "")
            try:
                deploy_ts = time.mktime(time.strptime(started, "%Y-%m-%dT%H:%M:%SZ"))
            except Exception:
                continue
            if deploy_ts < cutoff:
                break
            revision = entry.get("source", [{}])[0].get("revision", "")
            if not revision or len(revision) < 7:
                continue
            # Query Forgejo commits for this SHA range
            try:
                commits = fetch_json(
                    f"{FORGEJO_URL}/api/v1/repos/{REPO}/commits?sha={revision}&limit=1",
                    headers=HEADERS_FG
                )
                if commits:
                    commit_date = commits[0].get("commit", {}).get("author", {}).get("date", "")
                    if commit_date:
                        first_commit_ts = time.mktime(
                            time.strptime(commit_date, "%Y-%m-%dT%H:%M:%SZ")
                        )
                        lt_hours = (deploy_ts - first_commit_ts) / 3600
                        lead_times.append(lt_hours)
            except Exception:
                pass

        if not lead_times:
            return 0.0, 0
        lead_times.sort()
        median = lead_times[len(lead_times) // 2]
        return round(median, 2), len(lead_times)

    def change_failure_rate(app):
        """Return (failed / total) ratio over last 30 days."""
        deploys = deployments_30d(app)
        if not deploys:
            return 0.0, 0, 0
        total = len(deploys)
        failed = sum(1 for d in deploys if not d["succeeded"])
        return round(failed / total, 4), failed, total

    def mttr(app):
        """Mean time to recovery: median gap from failed sync to next successful sync."""
        deploys = deployments_30d(app)
        gaps = []
        i = 0
        while i < len(deploys):
            if not deploys[i]["succeeded"]:
                # Look for next succeeded
                j = i + 1
                while j < len(deploys) and not deploys[j]["succeeded"]:
                    j += 1
                if j < len(deploys):
                    gap_hours = (deploys[j]["ts"] - deploys[i]["ts"]) / 3600
                    gaps.append(gap_hours)
                i = j
            else:
                i += 1
        if not gaps:
            return 0.0, 0
        gaps.sort()
        return round(gaps[len(gaps) // 2], 2), len(gaps)

    def deployment_frequency(app):
        """Deployments per day over last 30 days."""
        deploys = deployments_30d(app)
        succeeded = [d for d in deploys if d["succeeded"]]
        return round(len(succeeded) / 30.0, 3), len(succeeded)

    def collect():
        while True:
            new_metrics = {}
            for app in APPS:
                app = app.strip()
                df_val, df_cnt       = deployment_frequency(app)
                lt_val, lt_cnt       = lead_time(app)
                cfr_val, cfr_fail, _ = change_failure_rate(app)
                mttr_val, mttr_cnt   = mttr(app)

                new_metrics[app] = {
                    "deployment_frequency_total":     df_cnt,
                    "deployment_frequency_per_day":   df_val,
                    "lead_time_hours":                lt_val,
                    "lead_time_samples":              lt_cnt,
                    "change_failure_rate":            cfr_val,
                    "change_failure_count":           cfr_fail,
                    "mttr_hours":                    mttr_val,
                    "mttr_samples":                  mttr_cnt,
                }

            with metrics_lock:
                metrics.clear()
                metrics.update(new_metrics)

            time.sleep(INTERVAL)

    # ── Prometheus exposition format ─────────────────────────────────────────────
    def build_output():
        out_lines = [
            "# HELP dora_deployment_frequency_per_day Deployments per day (30d rolling avg)",
            "# TYPE dora_deployment_frequency_per_day gauge",
            "# HELP dora_lead_time_hours Median hours from first commit to deploy",
            "# TYPE dora_lead_time_hours gauge",
            "# HELP dora_change_failure_rate Failed deploys / total deploys (30d)",
            "# TYPE dora_change_failure_rate gauge",
            "# HELP dora_mttr_hours Median hours from failure to recovery",
            "# TYPE dora_mttr_hours gauge",
            "# HELP dora_deployment_total Total successful deployments (30d)",
            "# TYPE dora_deployment_total counter",
            "# HELP dora_failure_total Total failed deployments (30d)",
            "# TYPE dora_failure_total counter",
            "",
        ]
        with metrics_lock:
            for app, m in metrics.items():
                app_label = app.replace("-", "_")
                base = f'dora{{app="{app}"}}'
                out_lines += [
                    f"dora_deployment_frequency_per_day{{{base}}} {m['deployment_frequency_per_day']}",
                    f"dora_deployment_frequency_total{{{base}}} {m['deployment_frequency_total']}",
                    f"dora_lead_time_hours{{{base}}} {m['lead_time_hours']}",
                    f"dora_change_failure_rate{{{base}}} {m['change_failure_rate']}",
                    f"dora_failure_total{{{base}}} {m['change_failure_count']}",
                    f"dora_mttr_hours{{{base}}} {m['mttr_hours']}",
                ]
        return "\n".join(out_lines).encode()

    # ── HTTP server ────────────────────────────────────────────────────────────
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/metrics":
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; version=0.0.4")
                self.end_headers()
                self.wfile.write(build_output())
            elif self.path == "/health":
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"OK")
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, fmt, *args):
            pass   # silence access logs

    def main():
        t = threading.Thread(target=collect, daemon=True)
        t.start()
        srv = http.server.HTTPServer(("0.0.0.0", METRICS_PORT), Handler)
        print(f"DORA exporter listening on :{METRICS_PORT}", flush=True)
        srv.serve_forever()

    if __name__ == "__main__":
        main()
    '';
  in
    pkgs.writeText "dora-exporter-configmap.yaml" ''
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: dora-exporter
        namespace: dora
      data:
        exporter.py: |
    '' + exporterScript + "\n";

  # ── DORA Exporter Deployment ─────────────────────────────────────────────────
  doraExporterDeployment = ''
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: dora-exporter
      namespace: dora
      labels:
        app.kubernetes.io/name: dora-exporter
    spec:
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/name: dora-exporter
      template:
        metadata:
          labels:
            app.kubernetes.io/name: dora-exporter
        spec:
          containers:
          - name: exporter
            image: python:3.12-slim
            command: ["python3", "/config/exporter.py"]
            ports:
            - containerPort: 8080
              name: http
            livenessProbe:
              httpGet:
                path: /health
                port: 8080
              initialDelaySeconds: 10
              periodSeconds: 30
            readinessProbe:
              httpGet:
                path: /health
                port: 8080
              initialDelaySeconds: 5
              periodSeconds: 10
            resources:
              requests:
                cpu: 10m
                memory: 32Mi
              limits:
                cpu: 200m
                memory: 128Mi
            volumeMounts:
            - name: config
              mountPath: /config
              readOnly: true
            env:
            - name: ARGO_URL
              value: "http://argocd-server.argocd:80"
            - name: FORGEJO_URL
              value: "http://forgejo-http.forgejo:3000"
            - name: APPS
              value: "orkestr"
            - name: REPO
              value: "QuadCoreTech/orkestr"
            - name: INTERVAL
              value: "300"
          volumes:
          - name: config
            configMap:
              name: dora-exporter
              defaultMode: 0555
  '';

  # ── DORA Exporter Service ────────────────────────────────────────────────────
  doraExporterService = ''
    apiVersion: v1
    kind: Service
    metadata:
      name: dora-exporter
      namespace: dora
      labels:
        app.kubernetes.io/name: dora-exporter
    spec:
      type: ClusterIP
      ports:
      - port: 8080
        targetPort: 8080
        protocol: TCP
        name: http
      selector:
        app.kubernetes.io/name: dora-exporter
  '';

  # ── DORA Exporter ServiceMonitor (for Prometheus scraping) ──────────────────
  doraExporterServiceMonitor = ''
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: dora-exporter
      namespace: dora
      labels:
        app.kubernetes.io/name: dora-exporter
        release: prometheus   # matches Prometheus selector
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: dora-exporter
      endpoints:
      - port: http
        interval: 60s
        scrapeTimeout: 30s
        path: /metrics
  '';

  # ── ArgoCD ServiceMonitor (exposes argocd_server_sync_total, etc.) ────────────
  argocdServiceMonitor = ''
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: argocd
      namespace: argocd
      labels:
        app.kubernetes.io/name: argocd
        release: prometheus
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: argocd-server
      endpoints:
      - port: metrics
        interval: 60s
        path: /metrics
  '';

  # ── DORA Grafana Dashboard ───────────────────────────────────────────────────
  doraGrafanaDashboard = let
    dashboardJson = pkgs.writeText "dora-dashboard.json" (builtins.toJSON {
      title = "DORA Metrics - Orkestr";
      uid = "dora-metrics-orkestr";
      schemaVersion = 38;
      version = 1;
      refresh = "5m";
      timezone = "browser";
      tags = ["dora", "orkestr", "delivery"];
      templating.list = [
        {
          name = "app";
          type = "dropdown";
          query = "label_values(dora, app)";
          current = { text = "orkestr"; value = "orkestr"; };
          includeAll = false;
        }
      ];
      panels = [
        # ── Deployment Frequency ─────────────────────────────────────────────
        {
          type = "stat";
          title = "Deployment Frequency (per day)";
          gridPos = { h = 6; w = 6; x = 0; y = 0; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_deployment_frequency_per_day{app="$app"}'';
            legendFormat = "per day";
          }];
          fieldConfig.defaults.unit = "none";
          options.legend.displayMode = "list";
        }
        {
          type = "timeseries";
          title = "Deployments Over Time";
          gridPos = { h = 6; w = 12; x = 6; y = 0; };
          datasource = "Prometheus";
          targets = [{
            expr = ''sum(increase(dora_deployment_total{app="$app"}[1d]))'';
            legendFormat = "successful / day";
          }];
          fieldConfig.defaults.unit = "none";
          legend.displayMode = "list";
        }
        {
          type = "stat";
          title = "Total Deployments (30d)";
          gridPos = { h = 6; w = 6; x = 18; y = 0; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_deployment_frequency_total{app="$app"}'';
            legendFormat = "total";
          }];
          fieldConfig.defaults.unit = "none";
        }
        # ── Lead Time ───────────────────────────────────────────────────────
        {
          type = "stat";
          title = "Lead Time (median hours)";
          gridPos = { h = 6; w = 6; x = 0; y = 6; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_lead_time_hours{app="$app"}'';
            legendFormat = "hours";
          }];
          fieldConfig.defaults.unit = "h";
          fieldConfig.defaults.thresholds.steps = [
            { value = null; color = "green"; }
            { value = 1; color = "green"; }
            { value = 24; color = "yellow"; }
            { value = 168; color = "orange"; }
            { value = 720; color = "red"; }
          ];
          fieldConfig.defaults.fieldMin = 0;
          mappings = [];
          options.colorMode = "value";
          options.graphMode = "none";
        }
        {
          type = "timeseries";
          title = "Lead Time Trend";
          gridPos = { h = 6; w = 12; x = 6; y = 6; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_lead_time_hours{app="$app"}'';
            legendFormat = "hours";
          }];
          fieldConfig.defaults.unit = "h";
          legend.displayMode = "list";
        }
        {
          type = "stat";
          title = "Lead Time Samples";
          gridPos = { h = 6; w = 6; x = 18; y = 6; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_lead_time_samples{app="$app"}'';
            legendFormat = "samples";
          }];
          fieldConfig.defaults.unit = "none";
        }
        # ── Change Failure Rate ─────────────────────────────────────────────
        {
          type = "gauge";
          title = "Change Failure Rate";
          gridPos = { h = 6; w = 6; x = 0; y = 12; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_change_failure_rate{app="$app"} * 100'';
            legendFormat = "%";
          }];
          fieldConfig.defaults.unit = "percent";
          fieldConfig.defaults.min = 0;
          fieldConfig.defaults.max = 100;
          fieldConfig.defaults.thresholds.steps = [
            { value = null; color = "green"; }
            { value = 5; color = "green"; }
            { value = 15; color = "yellow"; }
            { value = 30; color = "orange"; }
            { value = 50; color = "red"; }
          ];
          options.colorMode = "value";
          options.graphMode = "area";
        }
        {
          type = "timeseries";
          title = "Change Failure Rate Trend";
          gridPos = { h = 6; w = 12; x = 6; y = 12; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_change_failure_rate{app="$app"} * 100'';
            legendFormat = "CFR %";
          }];
          fieldConfig.defaults.unit = "percent";
          legend.displayMode = "list";
        }
        {
          type = "stat";
          title = "Failed Deployments (30d)";
          gridPos = { h = 6; w = 6; x = 18; y = 12; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_failure_total{app="$app"}'';
            legendFormat = "failed";
          }];
          fieldConfig.defaults.unit = "none";
          fieldConfig.defaults.thresholds.steps = [
            { value = null; color = "green"; }
            { value = 1; color = "yellow"; }
            { value = 5; color = "red"; }
          ];
          options.colorMode = "value";
        }
        # ── MTTR ───────────────────────────────────────────────────────────
        {
          type = "stat";
          title = "MTTR (median hours)";
          gridPos = { h = 6; w = 6; x = 0; y = 18; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_mttr_hours{app="$app"}'';
            legendFormat = "hours";
          }];
          fieldConfig.defaults.unit = "h";
          fieldConfig.defaults.thresholds.steps = [
            { value = null; color = "green"; }
            { value = 1; color = "green"; }
            { value = 24; color = "yellow"; }
            { value = 72; color = "orange"; }
            { value = 168; color = "red"; }
          ];
          options.colorMode = "value";
          options.graphMode = "none";
        }
        {
          type = "timeseries";
          title = "MTTR Trend";
          gridPos = { h = 6; w = 12; x = 6; y = 18; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_mttr_hours{app="$app"}'';
            legendFormat = "hours";
          }];
          fieldConfig.defaults.unit = "h";
          legend.displayMode = "list";
        }
        {
          type = "stat";
          title = "MTTR Samples";
          gridPos = { h = 6; w = 6; x = 18; y = 18; };
          datasource = "Prometheus";
          targets = [{
            expr = ''dora_mttr_samples{app="$app"}'';
            legendFormat = "recoveries";
          }];
          fieldConfig.defaults.unit = "none";
        }
        # ── DORA Rating Summary ─────────────────────────────────────────────
        {
          type = "text";
          title = "DORA Rating Summary";
          gridPos = { h = 3; w = 24; x = 0; y = 24; };
          options.text.value = ''
            ## DORA Performance Rating (30-day window)

            | Metric | Value | Elite | High | Medium | Low |
            |--------|-------|-------|------|--------|-----|
            | Deployment Frequency | ''${__data.fields["Deployment Frequency (median hours)"] || "—"}'' per day | On-demand | Daily–weekly | Weekly–monthly | Monthly–semi-annually |
            | Lead Time | ''${__data.fields["Lead Time (median hours)"] || "—"}'' hours | < 1 hour | 1 day – 1 week | 1 week – 1 month | > 1 month |
            | Change Failure Rate | ''${__data.fields["Change Failure Rate"] || "—"}'' | < 5% | 5–10% | 10–15% | > 15% |
            | MTTR | ''${__data.fields["MTTR (median hours)"] || "—"}'' hours | < 1 hour | < 1 day | 1 day – 1 week | > 1 week |
          '';
        }
      ];
    });
  in
    pkgs.writeText "dora-dashboard-configmap.yaml" ''
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: grafana-dashboard-dora-metrics
        namespace: grafana
        labels:
          grafana_dashboard: "1"
      data:
        dora-metrics.json: |-
    '' + builtins.readFile dashboardJson + "\n";
in {
  chartFiles = {};

  inlineFiles = {
    "20a-dora-namespace.yaml"                  = doraNamespace;
    "20b-dora-exporter-configmap.yaml"         = doraExporterConfigMap;
    "20c-dora-exporter-deployment.yaml"         = doraExporterDeployment;
    "20d-dora-exporter-service.yaml"            = doraExporterService;
    "20e-dora-exporter-servicemonitor.yaml"     = doraExporterServiceMonitor;
    "20f-argocd-servicemonitor.yaml"            = argocdServiceMonitor;
    "20g-dora-dashboard-configmap.yaml"        = doraGrafanaDashboard;
  };

  order = [
    "20a-dora-namespace.yaml"
    "20b-dora-exporter-configmap.yaml"
    "20c-dora-exporter-deployment.yaml"
    "20d-dora-exporter-service.yaml"
    "20e-dora-exporter-servicemonitor.yaml"
    "20f-argocd-servicemonitor.yaml"
    "20g-dora-dashboard-configmap.yaml"
  ];
}
