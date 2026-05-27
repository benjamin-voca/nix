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
      values = import ../../lib/argocd-values.nix {
        domain = "argocd.quadtech.dev";
        serverUrl = "https://argocd.quadtech.dev";
        serverReplicas = 1;
        controllerReplicas = 1;
        repoServerReplicas = 1;
        enableApplicationSet = true;
        enableNotifications = true;
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
