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
      flakeOutputs = {
        helmLib = import ./modules/outputs/helm.nix { inherit inputs lib; };
      };
      eval = lib.evalModules {
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/top.nix
        ];
      };
    in
      eval.config.flake // flakeOutputs;
}
