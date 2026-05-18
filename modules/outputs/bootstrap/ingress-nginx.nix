# Ingress-nginx bootstrap module
# Ingress controller with LoadBalancer (gets IP from MetalLB)
{
  pkgs,
  lib,
  charts,
  kubelib,
}: let
  ingressNginxChart =
    pkgs.lib.pipe
    {
      name = "ingress-nginx";
      chart = charts.kubernetes-ingress-nginx.ingress-nginx;
      namespace = "ingress-nginx";
      values = {
        controller = {
          service = {
            type = "LoadBalancer";
          };
        };
      };
    }
    [kubelib.buildHelmChart];
in {
  chartFiles = {
    "01-ingress-nginx.yaml" = ingressNginxChart;
  };

  inlineFiles = {};

  order = ["01-ingress-nginx.yaml"];
}
