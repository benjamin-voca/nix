{ inputs, flake, lib, ... }:

let
  imports = import ./imports.nix { inherit lib; };
in
{
  imports = imports;
  _module.args = { inherit inputs flake; };
}
