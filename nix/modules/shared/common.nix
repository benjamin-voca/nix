{ config, lib, ... }:

let
  inherit (lib) mkOption types;
  cfg = config.quadnix;
in {
  options.quadnix = {
    environment = mkOption {
      type = types.enum [ "dev" "staging" "prod" ];
      default = "prod";
      description = "Deployment environment label.";
    };

    versions = {
      kubernetes = mkOption {
        type = types.str;
        default = "1.29.3";
        description = "Pinned Kubernetes version for control-plane/worker.";
      };
      gitea = mkOption {
        type = types.str;
        default = "1.21.5";
        description = "Pinned Gitea version for server/runner.";
      };
    };

    paths = {
      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/quadnix";
        description = "Base state directory for QuadNix-managed services.";
      };
      configDir = mkOption {
        type = types.str;
        default = "/etc/quadnix";
        description = "Base config directory for QuadNix-managed services.";
      };
    };
  };

  config = {
    environment.etc."quadnix/environment".text = cfg.environment;
    environment.etc."quadnix/versions.json".text = builtins.toJSON cfg.versions;
    environment.etc."quadnix/paths.json".text = builtins.toJSON cfg.paths;
  };
}
