{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://charts.longhorn.io";
    chart = "longhorn";
    version = "1.11.0";
    chartHash = "sha256-090cfxyg9rz9hm32100nxbm3pq204bf3gah9cnx0bz2l75jh2mdk";
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
