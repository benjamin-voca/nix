{helmLib}: let
  chartConfig = import ../../../charts/rook-release/rook-ceph/default.nix;
  chart = helmLib.kubelib.downloadHelmChart chartConfig;
in {
  "rook-ceph" = helmLib.buildChart {
    name = "rook-ceph";
    inherit chart;
    namespace = "rook-ceph";
    values = {
      crds = {
        enabled = true;
      };

      csi = {
        enableRBDDriver = true;
        enableCephfsDriver = true;
        rookUseCsiOperator = false;
        enableNFSDriver = false;
        enableRBDSnapshotter = true;
        enableCephfsSnapshotter = true;
        enableNFSSnapshotter = false;
        kubeletDirPath = "/var/lib/kubernetes";
        csiRBDPluginVolume = [
          {
            name = "lib-modules";
            hostPath = {
              path = "/run/booted-system/kernel-modules/lib/modules";
            };
          }
        ];
        csiCephFSPluginVolume = [
          {
            name = "lib-modules";
            hostPath = {
              path = "/run/booted-system/kernel-modules/lib/modules";
            };
          }
        ];
      };

      resources = {
        requests = {
          cpu = "25m";
          memory = "128Mi";
        };
        limits = {
          memory = "256Mi";
        };
      };
    };
  };
}
