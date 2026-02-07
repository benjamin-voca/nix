{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://charts.verdaccio.org";
    chart = "verdaccio";
    version = "4.29.0";
    chartHash = "sha256-ZgTB51YUnWjJWV8NOY2qK1YixqGPHKj0UyDebhM51vk=";
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
