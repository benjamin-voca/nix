{
  description = "QuadNix NixOS Configuration";

  nixConfig = {
    extra-substituters = [
      "https://nixhelm.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    nixhelm.url = "github:farcaller/nixhelm";
    nix-kube-generators.url = "github:farcaller/nix-kube-generators";
    haumea.url = "github:nix-community/haumea";
    haumea.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: let
    lib = inputs.nixpkgs.lib;
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = lib.genAttrs systems;
    helmLibFor = system: let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      kubelib = inputs.nix-kube-generators.lib {inherit pkgs;};
      localCharts = inputs.haumea.lib.load {
        src = ./charts;
        transformer = inputs.haumea.lib.transformers.liftDefault;
      };
      localChartsDerivations =
        builtins.mapAttrs (
          repo: charts:
            builtins.mapAttrs (
              name: chart:
                kubelib.downloadHelmChart {
                  repo = chart.repo;
                  chart = chart.chart;
                  version = chart.version;
                }
            )
            charts
        )
        localCharts;
      helmLib = import ./lib/helm {
        inherit (inputs) nixhelm nix-kube-generators;
        inherit pkgs system;
      };
    in
      helmLib // {chartsDerivations = localChartsDerivations;};
    flakeOutputs = {
      helmLib = forAllSystems (system: helmLibFor system);
      packages = forAllSystems (system: {
        inherit (inputs.nixhelm.packages.${system}) helmupdater;
        bootstrap = eval.config.flake.bootstrap.${system};
        boostrap = eval.config.flake.bootstrap.${system};
      });
      apps = forAllSystems (system: {
        inherit (inputs.nixhelm.apps.${system}) helmupdater;
      });
      chartsMetadata = inputs.haumea.lib.load {
        src = ./charts;
        transformer = inputs.haumea.lib.transformers.liftDefault;
      };
      chartsDerivations = forAllSystems (system: helmLibFor system).chartsDerivations;
    };

    eval = lib.evalModules {
      specialArgs = {inherit inputs;};
      modules = [
        ./modules/top.nix
      ];
    };
  in
    eval.config.flake // flakeOutputs;
}
