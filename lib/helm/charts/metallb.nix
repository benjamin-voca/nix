{ helmLib }:

{
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
    };
  };
}
