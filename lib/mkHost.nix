{ nixpkgs }:

name: system:
nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [ ../hosts/${name}/default.nix ];
}
