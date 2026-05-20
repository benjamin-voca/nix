{helmLib}: {
  promtail = helmLib.buildChart {
    name = "promtail";
    chart = helmLib.charts.grafana.promtail;
    namespace = "loki";
    values = {
      config = {
        clients = [
          {
            url = "http://loki.loki:3100/loki/api/v1/push";
          }
        ];
      };
      serviceMonitor = {
        enabled = true;
      };
    };
  };
}
