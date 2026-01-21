{ config, pkgs, ... }:

{
  imports = [
    ../profiles/kubernetes/helm.nix
  ];
}
