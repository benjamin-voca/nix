{ inputs, lib, ... }:

let
  imports = import ./imports.nix { inherit lib inputs; };
in
{
  imports = imports;
  _module.args = { inherit inputs; };
}
