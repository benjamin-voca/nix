{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://charts.verdaccio.org";
    chart = "verdaccio";
    version = "4.29.0";
    chartHash = "sha256-1yfn749nxpi0agsah74gl7324mibma6kj3azb74ni78lavkw2136";
  };
in
{
  verdaccio = helmLib.buildChart {
    name = "verdaccio";
    inherit chart;
    namespace = "verdaccio";
    values = {
      service = {
        type = "ClusterIP";
      };
      ingress = {
        enabled = true;
        className = "nginx";
        paths = [ "/" ];
        hosts = [ "verdaccio.quadtech.dev" ];
        annotations = { };
        tls = [ ];
      };
      persistence = {
        enabled = true;
        size = "10Gi";
      };
    };
  };
}
