{ lib, pkgs }:

let
  yaml = pkgs.formats.yaml { };
in
{
  writeOne = name: manifest:
    yaml.generate "${name}.yaml" manifest;

  writeMany = name: manifests:
    pkgs.writeText "${name}.yaml" (
      lib.concatStringsSep "\n---\n" (
        lib.imap1 (
          i: manifest:
            builtins.readFile (yaml.generate "${name}-${toString i}.yaml" manifest)
        ) manifests
      )
    );
}
