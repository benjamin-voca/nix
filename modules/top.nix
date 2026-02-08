{ inputs, lib, ... }:

let
  imports = import ./imports.nix { inherit lib; };
in
{
  imports = imports;
}
