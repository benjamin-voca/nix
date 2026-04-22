{
  config,
  lib,
  inputs,
  ...
}: let
  systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
  forAllSystems = lib.genAttrs systems;
  helmLibFor = system: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in
    import ../../lib/helm {
      inherit (inputs) nixhelm nix-kube-generators;
      inherit pkgs system;
    };
  argocdChartFor = system: let
    helmLib = helmLibFor system;
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in
    helmLib.buildChart {
      name = "argocd";
      chart = helmLib.charts.argoproj.argo-cd;
      namespace = "argocd";
      values = {
        global = {
          domain = "argocd.quadtech.dev";
        };

        configs = {
          cm = {
            "server.insecure" = true;
            url = "https://argocd.quadtech.dev";
          };
          params = {
            "server.insecure" = true;
          };
          secret = {
            argocdServerAdminPassword = "PLACEHOLDER";
          };
        };

        server = {
          replicas = 1;
          service = {
            type = "ClusterIP";
          };
        };

        redis = {
          enabled = true;
        };

        redis-ha = {
          enabled = false;
        };

        controller = {
          replicas = 1;
        };

        repoServer = {
          replicas = 1;
        };

        applicationSet = {
          enabled = true;
        };

        notifications = {
          enabled = true;
        };

        global.image.tag = "v2.9.3";
      };
    };
in {
  config.flake.helmLib = forAllSystems (system: helmLibFor system);

  config.flake.helmCharts = forAllSystems (
    system: let
      helmLib = helmLibFor system;
      charts = import ../../lib/helm/charts {inherit helmLib;};
    in
      charts // {argocd = argocdChartFor system;}
  );

  config.flake.chartsDerivations = inputs.nixhelm.chartsDerivations;
  config.flake.chartsMetadata = inputs.nixhelm.chartsMetadata;
}
