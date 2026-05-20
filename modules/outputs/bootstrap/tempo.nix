# Tempo bootstrap module
# Tempo namespace + chart for distributed tracing
{lib, existingCharts}: let
  tempoChart = existingCharts.tempo;

  tempoNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: tempo
      labels:
        app.kubernetes.io/name: tempo
  '';
in {
  chartFiles = {
    "12e-tempo-chart.yaml" = tempoChart;
  };

  inlineFiles = {
    "11a-tempo-namespace.yaml" = tempoNamespace;
  };

  order = [
    "11a-tempo-namespace.yaml"
    "12e-tempo-chart.yaml"
  ];
}
