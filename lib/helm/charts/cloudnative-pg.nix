{ helmLib }:

{
  cloudnative-pg = helmLib.buildChart {
    name = "cloudnative-pg";
    chart = helmLib.charts.cloudnative-pg.cloudnative-pg;
    namespace = "cnpg-system";
    values = {
      monitoring = {
        podMonitorEnabled = false;
      };
    };
  };
}
