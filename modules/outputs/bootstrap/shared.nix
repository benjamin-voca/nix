# Shared helpers for bootstrap output modules
# These are common utility functions used across all bootstrap sub-modules.
{
  lib,
  inputs,
}: let
  systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
  forAllSystems = lib.genAttrs systems;

  pkgsFor = system: inputs.nixpkgs.legacyPackages.${system};

  helmLibFor = system: let
    pkgs = pkgsFor system;
  in
    import ../../../lib/helm {
      inherit (inputs) nixhelm nix-kube-generators;
      inherit pkgs system;
    };

  chartsFor = system: inputs.nixhelm.chartsDerivations.${system};

  composableFor = system: let
    pkgs = pkgsFor system;
  in
    import ../../../lib/helm/composable.nix {inherit pkgs;};

  kubelibFor = system: let
    pkgs = pkgsFor system;
  in
    inputs.nix-kube-generators.lib {inherit pkgs;};

  existingChartsFor = system: let
    helmLib = helmLibFor system;
  in
    import ../../../lib/helm/charts {inherit helmLib;};
in {
  inherit systems forAllSystems pkgsFor helmLibFor chartsFor composableFor kubelibFor existingChartsFor;
}
