{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.cloudflared-k8s;
  
  # Convert Nix values to YAML format
  toYAML = v:
    if builtins.isBool v then (if v then "true" else "false")
    else if builtins.isInt v then toString v
    else if builtins.isString v then v
    else toString v;
in {
  options.services.cloudflared-k8s = {
    enable = mkEnableOption "Cloudflare Tunnel with Kubernetes service routing";

    tunnelId = mkOption {
      type = types.str;
      description = "Cloudflare Tunnel UUID";
      example = "9832df66-f04a-40ea-b004-f6f9b100eb14";
    };

    credentialsFile = mkOption {
      type = types.path;
      description = ''
        Path to the tunnel credentials JSON file.
        
        Can be a direct path like "/home/user/.cloudflared/credentials.json"
        or a SOPS secret like "config.sops.secrets.cloudflared-credentials.path"
      '';
      example = "/run/secrets/cloudflared-credentials.json";
    };

    routes = mkOption {
      type = types.listOf (types.submodule {
        options = {
          hostname = mkOption {
            type = types.str;
            description = "Public hostname for this route";
            example = "gitea.quadtech.dev";
          };

          service = mkOption {
            type = types.str;
            description = "Backend service URL or special service type";
            example = "http://localhost:3000";
          };

          originRequest = mkOption {
            type = types.nullOr (types.attrs);
            default = null;
            description = "Origin request options for this route";
          };
        };
      });
      default = [];
      description = "List of ingress routes for the tunnel";
    };

    catchAll = mkOption {
      type = types.str;
      default = "http_status:404";
      description = "Catch-all service for unmatched requests";
    };

    logLevel = mkOption {
      type = types.enum [ "debug" "info" "warn" "error" "fatal" ];
      default = "info";
      description = "Log level for cloudflared";
    };
  };

  config = mkIf cfg.enable {
    # Create configuration file
    environment.etc."cloudflared/config.yml".text = ''
      tunnel: ${cfg.tunnelId}
      credentials-file: ${cfg.credentialsFile}
      loglevel: ${cfg.logLevel}

      ingress:
      ${concatMapStringsSep "\n" (route: ''
        - hostname: ${route.hostname}
          service: ${route.service}
      ${optionalString (route.originRequest != null) ''
          originRequest:
      ${concatStringsSep "\n" (mapAttrsToList (k: v: "      ${k}: ${toYAML v}") route.originRequest)}
      ''}
      '') cfg.routes}
        - service: ${cfg.catchAll}
    '';

    # Create state directory
    systemd.tmpfiles.rules = [
      "d /var/lib/cloudflared 0755 root root -"
    ];

    # Systemd service
    systemd.services.cloudflared = {
      description = "Cloudflare Tunnel";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run";
        Restart = "always";
        RestartSec = "5s";
        
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/cloudflared" ];
      };
    };

    # Ensure cloudflared package is installed
    environment.systemPackages = [ pkgs.cloudflared ];
  };
}
