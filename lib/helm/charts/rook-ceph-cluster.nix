{ helmLib }:

let
  chartConfig = import ../../../charts/rook-release/rook-ceph-cluster/default.nix;
  chart = helmLib.kubelib.downloadHelmChart chartConfig;
in
{
  "rook-ceph-cluster" = helmLib.buildChart {
    name = "rook-ceph-cluster";
    inherit chart;
    namespace = "rook-ceph";
    values = {
      operatorNamespace = "rook-ceph";
      toolbox.enabled = true;

      cephClusterSpec = {
        dataDirHostPath = "/var/lib/rook";

        mon = {
          count = 1;
          allowMultiplePerNode = true;
        };

        mgr = {
          count = 1;
          allowMultiplePerNode = true;
        };

        dashboard = {
          enabled = true;
          ssl = false;
        };

        resources = {
          mon = {
            requests = {
              cpu = "250m";
              memory = "512Mi";
            };
            limits = {
              memory = "2Gi";
            };
          };

          mgr = {
            requests = {
              cpu = "100m";
              memory = "256Mi";
            };
            limits = {
              memory = "1Gi";
            };
          };

          "mgr-sidecar" = {
            requests = {
              cpu = "50m";
              memory = "40Mi";
            };
            limits = {
              memory = "100Mi";
            };
          };

          osd = {
            requests = {
              cpu = "250m";
              memory = "1Gi";
            };
            limits = {
              memory = "4Gi";
            };
          };

          prepareosd = {
            requests = {
              cpu = "100m";
              memory = "50Mi";
            };
          };

          crashcollector = {
            requests = {
              cpu = "50m";
              memory = "60Mi";
            };
            limits = {
              memory = "60Mi";
            };
          };

          exporter = {
            requests = {
              cpu = "25m";
              memory = "50Mi";
            };
            limits = {
              memory = "128Mi";
            };
          };

          logcollector = {
            requests = {
              cpu = "50m";
              memory = "100Mi";
            };
            limits = {
              memory = "1Gi";
            };
          };

          cleanup = {
            requests = {
              cpu = "100m";
              memory = "100Mi";
            };
            limits = {
              memory = "1Gi";
            };
          };
        };

        storage = {
          useAllNodes = false;
          useAllDevices = false;
          nodes = [
            {
              name = "backbone-01.local";
              devices = [
                {
                  name = "/dev/sda";
                }
              ];
            }
          ];
        };
      };

      cephBlockPools = [
        {
          name = "ceph-block-hdd";
          spec = {
            failureDomain = "host";
            replicated = {
              size = 1;
            };
            parameters = {
              compression_mode = "aggressive";
            };
          };
          storageClass = {
            enabled = true;
            name = "ceph-block";
            isDefault = true;
            reclaimPolicy = "Delete";
            allowVolumeExpansion = true;
            volumeBindingMode = "Immediate";
            parameters = {
              "csi.storage.k8s.io/provisioner-secret-name" = "rook-csi-rbd-provisioner";
              "csi.storage.k8s.io/provisioner-secret-namespace" = "rook-ceph";
              "csi.storage.k8s.io/controller-expand-secret-name" = "rook-csi-rbd-provisioner";
              "csi.storage.k8s.io/controller-expand-secret-namespace" = "rook-ceph";
              "csi.storage.k8s.io/node-stage-secret-name" = "rook-csi-rbd-node";
              "csi.storage.k8s.io/node-stage-secret-namespace" = "rook-ceph";
              imageFormat = "2";
              imageFeatures = "layering";
              "csi.storage.k8s.io/fstype" = "ext4";
            };
          };
        }
        # Add a second pool/storageClass when NVMe-backed OSDs are available.
      ];

      cephFileSystems = [
        {
          name = "ceph-filesystem";
          spec = {
            metadataPool = {
              failureDomain = "host";
              replicated = {
                size = 1;
              };
            };
            dataPools = [
              {
                failureDomain = "host";
                replicated = {
                  size = 1;
                };
                name = "data0";
              }
            ];
            metadataServer = {
              activeCount = 1;
              activeStandby = true;
              resources = {
                limits = {
                  memory = "2Gi";
                };
                requests = {
                  cpu = "250m";
                  memory = "512Mi";
                };
              };
            };
          };
          storageClass = {
            enabled = true;
            isDefault = false;
            name = "ceph-filesystem";
            pool = "data0";
            reclaimPolicy = "Delete";
            allowVolumeExpansion = true;
            volumeBindingMode = "Immediate";
            parameters = {
              "csi.storage.k8s.io/provisioner-secret-name" = "rook-csi-cephfs-provisioner";
              "csi.storage.k8s.io/provisioner-secret-namespace" = "rook-ceph";
              "csi.storage.k8s.io/controller-expand-secret-name" = "rook-csi-cephfs-provisioner";
              "csi.storage.k8s.io/controller-expand-secret-namespace" = "rook-ceph";
              "csi.storage.k8s.io/controller-publish-secret-name" = "rook-csi-cephfs-provisioner";
              "csi.storage.k8s.io/controller-publish-secret-namespace" = "rook-ceph";
              "csi.storage.k8s.io/node-stage-secret-name" = "rook-csi-cephfs-node";
              "csi.storage.k8s.io/node-stage-secret-namespace" = "rook-ceph";
              "csi.storage.k8s.io/fstype" = "ext4";
            };
          };
        }
      ];

      cephObjectStores = [
        {
          name = "ceph-objectstore";
          spec = {
            metadataPool = {
              failureDomain = "host";
              replicated = {
                size = 1;
              };
            };
            dataPool = {
              failureDomain = "host";
              replicated = {
                size = 1;
              };
            };
            preservePoolsOnDelete = true;
            gateway = {
              port = 80;
              instances = 1;
            };
          };
          storageClass = {
            enabled = true;
            name = "ceph-bucket";
            reclaimPolicy = "Delete";
            volumeBindingMode = "Immediate";
            parameters = {
              region = "us-east-1";
            };
          };
        }
      ];
    };
  };
}
