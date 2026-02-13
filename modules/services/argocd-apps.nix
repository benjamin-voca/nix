{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.quadnix.argocdApps;
in {
  options.services.quadnix.argocdApps = {
    enable = lib.mkEnableOption "ArgoCD Applications for GitOps";

    harbor = lib.mkEnableOption "Harbor registry via ArgoCD";
    verdaccio = lib.mkEnableOption "Verdaccio NPM registry via ArgoCD";
  };

  config = lib.mkIf cfg.enable {
    # Placeholder - actual ArgoCD Applications are defined in bootstrap.nix
  };
}
