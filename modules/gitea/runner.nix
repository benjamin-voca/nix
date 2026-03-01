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

    checkUrl = mkOption {
      type = types.str;
      default = cfg.registrationUrl;
      description = "URL to check for Gitea availability before starting.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/gitea-runner";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.gitea-runner = {
      description = "Gitea actions runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      requires = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${runnerPkg}/bin/act_runner daemon --config /etc/gitea/runner/config.yaml";
        Restart = "always";
        RestartSec = "10s";
        StateDirectory = "gitea-runner";
        WorkingDirectory = "/var/lib/gitea-runner";
      };
      preStart = ''
        mkdir -p /etc/gitea/runner /var/lib/gitea-runner
        
        echo "Waiting for Gitea to be accessible..."
        for i in $(seq 1 60); do
          if curl -fsSk "${cfg.checkUrl}" >/dev/null 2>&1; then
            break
          fi
          echo "Waiting for Gitea..."
          sleep 5
        done
        
        cat > /etc/gitea/runner/config.yaml << EOF
runner:
  name: ${cfg.instanceName}
  labels:
${lib.concatMapStrings (l: "    - ${l}\n") cfg.labels}  token: $(cat ${cfg.tokenFile})
  url: ${cfg.registrationUrl}
  state_dir: ${cfg.stateDir}
EOF
        # Register runner if not already registered
        if [ ! -f /var/lib/gitea-runner/.runner ]; then
          cd /var/lib/gitea-runner
          TOKEN=$(cat ${cfg.tokenFile})
          ${runnerPkg}/bin/act_runner register --instance ${cfg.registrationUrl} --token "$TOKEN" --name ${cfg.instanceName} --no-interactive || true
        fi
      '';
    };
  };
}
