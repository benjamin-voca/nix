{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.services.gitea.runner;
  yaml = pkgs.formats.yaml { };
  runnerPkg = cfg.package;
in {
  options.services.gitea.runner = {
    enable = mkEnableOption "Gitea actions runner";

    package = mkOption {
      type = types.package;
      default = pkgs.gitea-actions-runner;
      description = "Runner package to execute workflows.";
    };

    registrationUrl = mkOption {
      type = types.str;
      default = "https://gitea.quadtech.dev";
    };

    tokenFile = mkOption {
      type = types.path;
      description = "Path to the runner registration token file.";
    };

    labels = mkOption {
      type = types.listOf types.str;
      default = [ "linux" "x86_64" ];
    };

    instanceName = mkOption {
      type = types.str;
      default = "quadnix-runner";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/gitea-runner";
    };
  };

  config = mkIf cfg.enable {
    environment.etc."gitea/runner/config.yaml".source = yaml.generate "gitea-runner.yaml" {
      runner = {
        name = cfg.instanceName;
        labels = cfg.labels;
        token = "${builtins.readFile cfg.tokenFile}";
        url = cfg.registrationUrl;
        state_dir = cfg.stateDir;
      };
    };

    systemd.services.gitea-runner = {
      description = "Gitea actions runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${runnerPkg}/bin/act_runner daemon --config /etc/gitea/runner/config.yaml";
        Restart = "always";
        StateDirectory = "gitea-runner";
      };
    };
  };
}
