{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://charts.longhorn.io";
    chart = "longhorn";
    version = "1.11.0";
    chartHash = "sha256-s1UBZTlU/AW6ZQmqN9wiQOA76uoWgCBGhenn9Hx3DCQ=";
  };
in
{
  longhorn = helmLib.buildChart {
    name = "longhorn";
    inherit chart;
    namespace = "longhorn-system";
    values = {
      persistence = {
        defaultClass = true;
        defaultClassReplicaCount = 1;
      };

      service = {
        ui = {
          type = "ClusterIP";
        };
      };
    };
  };
}
