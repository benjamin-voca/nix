{ nixhelm, nix-kube-generators, pkgs, system }:

let
  # Get the kubelib from nix-kube-generators
  kubelib = nix-kube-generators.lib { inherit pkgs; };
  
  # Get charts from nixhelm
  charts = nixhelm.charts { inherit pkgs; };
  
  # Helper function to build a helm chart with values
  buildChart = { name, chart, namespace, values ? {} }:
    kubelib.buildHelmChart {
      inherit name chart namespace;
      values = values;
    };

  # Helper function to build multiple charts
  buildCharts = chartsConfig:
    builtins.listToAttrs (
      map (chartConfig: {
        name = chartConfig.name;
        value = buildChart chartConfig;
      }) chartsConfig
    );

in {
  inherit kubelib charts buildChart buildCharts;
  
  # Re-export useful functions
  inherit (kubelib) buildHelmChart;
}
