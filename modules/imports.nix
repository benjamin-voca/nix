{ lib }:

let
  inherit (lib) hasSuffix;
  recurse = dir:
    let
      entries = builtins.readDir dir;
    in
    lib.concatLists (lib.mapAttrsToList (name: type:
      let
        path = dir + "/${name}";
      in
      if type == "directory" then
        if name == "hardware" then [] else recurse path
      else if type == "regular" && hasSuffix ".nix" name && name != "imports.nix" && name != "top.nix" then
        [ path ]
      else
        []
    ) entries);
in
recurse ./. 
