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
  };

  outputs = inputs:
    let
      lib = inputs.nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = lib.genAttrs systems;
      helmLibFor = system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
          import ./lib/helm {
            inherit (inputs) nixhelm nix-kube-generators;
            inherit pkgs system;
          };
      argocdChartFor = system:
        let
          helmLib = helmLibFor system;
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
                  argocdServerAdminPassword = "$2a$10$bX.6MmE5x1n.KlTA./3ax.xXzgP5CzLu1CyFyvMnEeh.vN9tDVVLC";
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
      flakeOutputs = {
        helmLib = forAllSystems (system: helmLibFor system);
        argocdChart = forAllSystems (system: argocdChartFor system);
      };
      eval = lib.evalModules {
        specialArgs = { inherit inputs; argocdChart = flakeOutputs.argocdChart; };
        modules = [
          ./modules/top.nix
        ];
      };
    in
      eval.config.flake // flakeOutputs;
}
