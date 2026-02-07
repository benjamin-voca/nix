{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/";
    chart = "infisical-standalone";
    version = "1.7.2";
    chartHash = "sha256-1ygl1jn0siiz24j2air3chxw8f19kvrmff1pbw92iqnmpgzm4ps6";
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
      };

      redis = {
        enabled = false;
      };
    };
  };
}
