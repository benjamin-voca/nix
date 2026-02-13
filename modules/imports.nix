{ lib, inputs }:

let
  inherit (lib) hasSuffix;
  filesIn = dir:
    let
      entries = builtins.readDir dir;
      files = lib.mapAttrsToList (name: type:
        if type == "regular" && hasSuffix ".nix" name
        then dir + "/${name}"
        else null
      ) entries;
    in
      builtins.filter (path: path != null) files;
in
  filesIn ./options
  ++ filesIn ./outputs
  ++ filesIn ./hosts
  ++ filesIn ./lib
