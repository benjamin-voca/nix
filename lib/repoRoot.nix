{ lib }:
let
  # Helper to get the repository root directory
  # Usage: repoRoot + "/nix/modules/shared/common.nix"
  repoRoot = builtins.toPath (builtins.dirOf (builtins.toString ../.));
in
{
  inherit repoRoot;
}
