{ nixpkgs }:

name: system:
nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ../profiles/base.nix
    ../hosts/${name}/default.nix
  ];
}
