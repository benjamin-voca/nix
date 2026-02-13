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
        annotations = {
          "nginx.ingress.kubernetes.io/ssl-redirect" = "false";
          "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
        };
        tls = [ { hosts = [ "verdaccio.quadtech.dev" ]; secretName = "verdaccio-tls"; } ];
      };
      persistence = {
        enabled = true;
        existingClaim = "verdaccio-data";
      };
      volumes = [
        {
          name = "verdaccio-data";
          hostPath = {
            path = "/var/lib/verdaccio";
            type = "Directory";
          };
        }
      ];
      volumeMounts = [
        {
          name = "verdaccio-data";
          mountPath = "/verdaccio/storage";
          subPath = "storage";
        }
        {
          name = "verdaccio-data";
          mountPath = "/verdaccio/conf";
          subPath = "conf";
        }
      ];
      securityContext = {
        fsGroup = 10001;
        runAsUser = 10001;
        runAsGroup = 10001;
      };
    };
  };
}
