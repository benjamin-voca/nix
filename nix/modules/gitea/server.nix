{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.services.gitea;
  ini = pkgs.formats.ini { };
  giteaUser = lib.attrByPath [ "services" "gitea" "user" ] "gitea" config;
  giteaPkg = lib.attrByPath [ "services" "gitea" "package" ] pkgs.gitea config;

  dbConfig = {
    database = {
      DB_TYPE = cfg.database.type;
      HOST = cfg.database.host;
      PORT = cfg.database.port;
      NAME = cfg.database.name;
      USER = cfg.database.user;
      PASSWD = if cfg.database.passwordFile == null
        then ""
        else builtins.readFile cfg.database.passwordFile;
      SSL_MODE = cfg.database.sslMode;
    };
  };

  sshConfig = {
    ssh = {
      ENABLE_SSH = cfg.ssh.enable;
      SSH_LISTEN_PORT = cfg.ssh.port;
      SSH_LISTEN_HOST = cfg.ssh.listenHost;
      SSH_AUTHORIZED_KEYS_ONLY = cfg.ssh.authorizedKeysOnly;
    };
  };

  backupScript = pkgs.writeShellScript "gitea-backup" ''
    set -euo pipefail
    backup_dir="${cfg.backup.targetDir}"
    timestamp="$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"
    ${giteaPkg}/bin/gitea dump --file "$backup_dir/gitea-$timestamp.zip"
    ${pkgs.findutils}/bin/find "$backup_dir" -type f -name "gitea-*.zip" -mtime +${toString cfg.backup.retention} -delete
  '';

  migrateScript = pkgs.writeShellScript "gitea-migrate" ''
    set -euo pipefail
    ${giteaPkg}/bin/gitea migrate ${lib.concatStringsSep " " cfg.migrations.extraArgs}
  '';
in {
  options.services.gitea = {
    enable = mkEnableOption "Gitea service";

    database = {
      host = mkOption { type = types.str; default = "localhost"; };
      port = mkOption { type = types.int; default = 5432; };
      name = mkOption { type = types.str; default = "gitea"; };
      user = mkOption { type = types.str; default = "gitea"; };
      passwordFile = mkOption { type = types.nullOr types.path; default = null; };
      sslMode = mkOption { type = types.str; default = "disable"; };
    };

    ssh = {
      enable = mkEnableOption "Gitea SSH";
      port = mkOption { type = types.port; default = 22; };
      listenHost = mkOption { type = types.str; default = "0.0.0.0"; };
      authorizedKeysOnly = mkOption { type = types.bool; default = true; };
    };

    backup = {
      enable = mkEnableOption "Gitea backups";
      interval = mkOption { type = types.str; default = "daily"; };
      retention = mkOption { type = types.int; default = 30; };
      targetDir = mkOption { type = types.str; default = "/var/backups/gitea"; };
    };

    migrations = {
      enable = mkEnableOption "Gitea database migrations";
      extraArgs = mkOption { type = types.listOf types.str; default = []; };
    };
  };

  config = mkIf (cfg.enable or false) {
    environment.etc."gitea/conf/database.ini".source = ini.generate "database.ini" dbConfig;
    environment.etc."gitea/conf/ssh.conf".source = ini.generate "ssh.conf" sshConfig;
    environment.etc."gitea/conf/version".text = config.services.gitea.common.version;

    systemd.services.gitea-migrate = mkIf cfg.migrations.enable {
      description = "Run Gitea database migrations";
      before = [ "gitea.service" ];
      requiredBy = [ "gitea.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = giteaUser;
      };
      script = migrateScript;
    };

    systemd.services.gitea-backup = mkIf cfg.backup.enable {
      description = "Gitea backup job";
      serviceConfig = {
        Type = "oneshot";
        User = giteaUser;
      };
      script = backupScript;
    };

    systemd.timers.gitea-backup = mkIf cfg.backup.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.backup.interval;
        Persistent = true;
      };
    };
  };
}
