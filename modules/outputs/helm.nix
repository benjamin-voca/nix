{ config, lib, inputs, ... }:

let
  systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  forAllSystems = lib.genAttrs systems;
  helmLibFor = system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
    in
      import ../../lib/helm {
        inherit (inputs) nixhelm nix-kube-generators;
        inherit pkgs system;
      };
in
{
  config.flake.helmLib = forAllSystems (system: helmLibFor system);

  config.flake.helmCharts = forAllSystems (system:
    let
      helmLib = helmLibFor system;
    in
      import ../../lib/helm/charts { inherit helmLib; }
  );

  config.flake.chartsDerivations = inputs.nixhelm.chartsDerivations;
  config.flake.chartsMetadata = inputs.nixhelm.chartsMetadata;
}
