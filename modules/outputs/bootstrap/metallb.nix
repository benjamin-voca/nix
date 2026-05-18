# MetalLB bootstrap module
# MetalLB chart + CRDs for IP address pool configuration
{
  pkgs,
  lib,
  charts,
  kubelib,
  composable,
}: let
  # MetalLB chart - use nixhelm's chart derivation directly
  # Note: MetalLB 0.15+ uses CRDs for configuration instead of configInline
  metallbChart =
    pkgs.lib.pipe
    {
      name = "metallb";
      chart = charts.metallb.metallb;
      namespace = "metallb";
      values = {
        controller = {
          resources = {
            requests = {
              cpu = "100m";
              memory = "128Mi";
            };
            limits = {
              cpu = "500m";
              memory = "256Mi";
            };
          };
        };
        speaker = {
          resources = {
            requests = {
              cpu = "50m";
              memory = "64Mi";
            };
            limits = {
              cpu = "200m";
              memory = "128Mi";
            };
          };
        };
      };
    }
    [kubelib.buildHelmChart];

  # MetalLB CRDs for IP address pool configuration (MetalLB 0.15+ uses CRDs)
  metallbIPAddressPool = ''
    apiVersion: metallb.io/v1beta1
    kind: IPAddressPool
    metadata:
      name: default
      namespace: metallb
    spec:
      addresses:
      - 192.168.1.240-192.168.1.250
      autoAssign: true
    ---
    apiVersion: metallb.io/v1beta1
    kind: L2Advertisement
    metadata:
      name: default
      namespace: metallb
    spec:
      ipAddressPools:
      - default

  '';
in {
  # Charts (store paths)
  chartFiles = {
    "00-metallb.yaml" = metallbChart;
  };

  # Inline YAML content (strings)
  inlineFiles = {
    "00-metallb-crds.yaml" = metallbIPAddressPool;
  };

  # Ordering for bootstrap.yaml concatenation
  order = ["00-metallb.yaml" "00-metallb-crds.yaml"];
}
