{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/";
    chart = "infisical-standalone";
    version = "1.0.8";
    chartHash = "sha256-gyDsPRxGY3U/7Qv9Z3Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9=";
  };
in
{
  infisical = helmLib.buildChart {
    name = "infisical";
    inherit chart;
    namespace = "infisical";
    values = {
      infisical = {
        kubeSecretRef = "infisical-secrets";
        replicaCount = 1;
      };

      ingress = {
        enabled = true;
        hostName = "infisical.quadtech.dev";
        ingressClassName = "nginx";
        nginx.enabled = false;
        annotations = { };
        tls = [ ];
      };

      postgresql = {
        enabled = false;
        useExistingPostgresSecret = {
          enabled = true;
          existingConnectionStringSecret = {
            name = "infisical-secrets";
            key = "DB_CONNECTION_URI";
          };
        };
      };

      redis = {
        enabled = false;
      };
    };
  };
}
