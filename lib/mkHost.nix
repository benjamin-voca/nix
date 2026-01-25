{ nixpkgs, sops-nix }:

name: system:
nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    sops-nix.nixosModules.sops
    ../profiles/base.nix
    ../hosts/${name}/default.nix
  ];
}
