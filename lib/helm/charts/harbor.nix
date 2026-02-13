{ helmLib }:

let
  chart = helmLib.kubelib.downloadHelmChart {
    repo = "https://helm.goharbor.io";
    chart = "harbor";
    version = "1.18.1";
    chartHash = "sha256-hAHyRjfDECw2XjM7Hrpbp4s2GaeSEz5IIjsA28pKmp8=";
  };
in
{
  harbor = helmLib.buildChart {
    name = "harbor";
    inherit chart;
    namespace = "harbor";
    values = {
      expose = {
        type = "ingress";
        tls = {
          enabled = true;
          certSource = "auto";
        };
        ingress = {
          hosts = {
            core = "harbor.quadtech.dev";
          };
          className = "nginx";
          annotations = {
            "nginx.ingress.kubernetes.io/proxy-body-size" = "0";
            "nginx.ingress.kubernetes.io/ssl-redirect" = "false";
          };
        };
      };

      externalURL = "https://harbor.quadtech.dev";

      persistence = {
        enabled = true;
        resourcePolicy = "keep";
        persistentVolumeClaim = {
          registry = {
            storageClass = "longhorn";
            size = "100Gi";
          };
          jobservice = {
            storageClass = "longhorn";
            size = "5Gi";
          };
          database = {
            storageClass = "longhorn";
            size = "10Gi";
          };
          redis = {
            storageClass = "longhorn";
            size = "5Gi";
          };
          trivy = {
            storageClass = "longhorn";
            size = "10Gi";
          };
        };
      };

      database = {
        type = "internal";
      };

      redis = {
        type = "internal";
      };

      portal = {
        replicas = 1;
      };

      core = {
        replicas = 1;
      };

      jobservice = {
        replicas = 1;
      };

      registry = {
        replicas = 1;
      };

      trivy = {
        enabled = true;
        replicas = 1;
      };

      notary = {
        enabled = false;
      };

      chartmuseum = {
        enabled = false;
      };
    };
  };
}
