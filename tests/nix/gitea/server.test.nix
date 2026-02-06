{ pkgs ? import <nixpkgs> { } }:

let
  lib = pkgs.lib;

  # Mock module to provide environment and systemd options for testing
  # Using attrsOf attrs to support nested attribute sets like environment.etc."path".text
  mockEnvironment = {
    options.environment = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
    };
  };

  mockSystemd = {
    options.systemd = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
    };
  };

  eval = lib.evalModules {
    modules = [
      mockEnvironment
      mockSystemd
      ({
        _file = "test-config";
        options = {
          nixpkgs = lib.mkOption {
            type = lib.types.attrs;
          };
        };
        config = {
          nixpkgs.hostPlatform = "aarch64-darwin";
          quad.environment = "dev";
        };
      })
      ../../../modules/shared/quad-common.nix
      ../../../modules/shared/gitea-common.nix
      ../../../modules/gitea/server.nix
      {
        services.gitea.enable = true;
        services.gitea.database.host = "db.internal";
        services.gitea.ssh.enable = true;
        services.gitea.backup.enable = true;
        services.gitea.migrations.enable = true;
      }
    ];
    specialArgs = { inherit pkgs; };
  };

  # Check that the database.ini is generated
  hasDbIni = eval.config.environment.etc ? "gitea/conf/database.ini";
  # Check that the backup timer is set to daily
  backupTimer = eval.config.systemd.timers."gitea-backup".timerConfig.OnCalendar or null;
in
assert hasDbIni;
assert backupTimer == "daily";
true
