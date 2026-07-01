{helmLib}: {
  metallb = helmLib.buildChart {
    name = "metallb";
    chart = helmLib.charts.metallb;
    namespace = "metallb";
    values = {
      # Resource limits
      controller = {
        resources = {
          requests = {
            cpu = "100m";
            memory = "128Mi";
          };
          limits = {
            cpu = "500m";
            memory = "256Mi";
          };
        };
      };

      speaker = {
        resources = {
          requests = {
            cpu = "50m";
            memory = "64Mi";
          };
          limits = {
            cpu = "200m";
            memory = "128Mi";
          };
        };
      };

      # metallb 0.16.0 ships an frr-k8s subchart whose
      # `service-monitor.yaml` template unconditionally reads
      # `.Values.prometheus.serviceMonitor.enabled`, but the upstream
      # values.yaml leaves that key commented out, so the render errors
      # with "nil pointer evaluating interface {}.serviceMonitor" on any
      # install. Pass an explicit (false) value through.
      frr-k8s = {
        prometheus = {
          serviceMonitor = {
            enabled = false;
          };
        };
      };
    };
  };
}
