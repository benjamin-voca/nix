{
  description = "QuadNix NixOS Configuration";

  # Flake-level Nix configuration for binary caches
  # This applies to nix flake commands (build, develop, etc.)
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
    # Note: nix-kube-generators doesn't have a nixpkgs input to override
  };

  outputs = { self, nixpkgs, sops-nix, deploy-rs, nixhelm, nix-kube-generators, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      
      # Helm library for each system
      helmLibFor = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
          import ./lib/helm {
            inherit nixhelm nix-kube-generators pkgs system;
          };
    in
    {
      nixosConfigurations = {
        backbone-01 = (import ./lib/mkHost.nix { inherit nixpkgs sops-nix; })
          "backbone-01" "x86_64-linux";

        backbone-02 = (import ./lib/mkHost.nix { inherit nixpkgs sops-nix; })
          "backbone-02" "x86_64-linux";

        frontline-01 = (import ./lib/mkHost.nix { inherit nixpkgs sops-nix; })
          "frontline-01" "x86_64-linux";

        frontline-02 = (import ./lib/mkHost.nix { inherit nixpkgs sops-nix; })
          "frontline-02" "x86_64-linux";
      };

      # Expose helm library and charts
      helmLib = forAllSystems (system: helmLibFor system);
      
      # Expose pre-configured charts
      helmCharts = forAllSystems (system:
        let
          helmLib = helmLibFor system;
        in
          import ./lib/helm/charts { inherit helmLib; }
      );

      # Expose nixhelm's chart derivations directly
      chartsDerivations = nixhelm.chartsDerivations;
      chartsMetadata = nixhelm.chartsMetadata;

      deploy = {
        nodes = {
          "backbone-01" = {
            hostname = "mainssh.quadtech.dev";
            profiles = {
              system = "./result";
            };
            sshUser = "root";
          };

          "backbone-02" = {
            hostname = "192.168.1.11";
            profiles = {
              system = "./result";
            };
            sshUser = "root";
          };

          "frontline-01" = {
            hostname = "192.168.1.20";
            profiles = {
              system = "./result";
            };
            sshUser = "root";
          };

          "frontline-02" = {
            hostname = "192.168.1.21";
            profiles = {
              system = "./result";
            };
            sshUser = "root";
          };
        };
      };
    };
}
