{ config, lib, ... }:

let
  inherit (lib) mkOption mkIf types;
  cfg = config.services.gitea.common;
in {
  options.services.gitea.common = {
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/gitea";
      description = "Gitea state directory.";
    };

    configDir = mkOption {
      type = types.str;
      default = "/etc/gitea";
      description = "Gitea config directory.";
    };

    user = mkOption {
      type = types.str;
      default = "gitea";
      description = "Gitea service user.";
    };

    group = mkOption {
      type = types.str;
      default = "gitea";
      description = "Gitea service group.";
    };

    version = mkOption {
      type = types.str;
      default = config.quad.versions.gitea;
      description = "Pinned Gitea version for the server.";
    };
  };

  config = mkIf (config.services.gitea.enable or false) {
    environment.etc."gitea/conf/common.json".text = builtins.toJSON {
      inherit (cfg) stateDir configDir user group version;
    };
  };
}
