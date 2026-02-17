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
      namespaceOverride = "longhorn-system";

      persistence = {
        defaultClass = true;
        defaultClassReplicaCount = 1;
      };

      service = {
        ui = {
          type = "ClusterIP";
        };
      };

      csiPlugin = {
        attacherImage = "";
        provisionerImage = "";
        pluginImage = "longhornio/longhorn-manager:v1.11.0";
        provisioner = {
          resources = {
            limits = {
              cpu = "100m";
              memory = "128Mi";
            };
            requests = {
              cpu = "10m";
              memory = "64Mi";
            };
          };
        };
       attacher = {
          resources = {
            limits = {
              cpu = "100m";
              memory = "128Mi";
            };
            requests = {
              cpu = "10m";
              memory = "64Mi";
            };
          };
        };
      };

      longhornManager = {
        resources = {
          limits = {
            cpu = "100m";
            memory = "256Mi";
          };
          requests = {
            cpu = "10m";
            memory = "64Mi";
          };
        };
      };

      longhornDriver = {
        resources = {
          limits = {
            cpu = "100m";
            memory = "256Mi";
          };
          requests = {
            cpu = "10m";
            memory = "64Mi";
          };
        };
      };

      longhornUI = {
        resources = {
          limits = {
            cpu = "100m";
            memory = "128Mi";
          };
          requests = {
            cpu = "10m";
            memory = "64Mi";
          };
        };
      };
    };
  };
}
