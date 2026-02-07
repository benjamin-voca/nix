{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.services.cloudflared-k8s;
  json = pkgs.formats.json { };

  configJson = {
    tunnel = cfg.tunnelId;
    credentials-file = cfg.credentialsFile;
    ingress = map (route:
      if route.originRequest == null
      then { inherit (route) hostname service; }
      else { inherit (route) hostname service originRequest; }
    ) cfg.routes
    ++ lib.optional (cfg.wildcardHostname != null) {
      hostname = cfg.wildcardHostname;
      service = "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80";
    }
    ++ [ { service = cfg.catchAll; } ];
  };

  routeType = types.submodule {
    options = {
      hostname = mkOption { type = types.str; };
      service = mkOption { type = types.str; };
      originRequest = mkOption {
        type = types.nullOr types.attrs;
        default = null;
      };
    };
  };
in {
  options.services.cloudflared-k8s = {
    enable = mkEnableOption "Cloudflare Tunnel for K8s services";

    tunnelId = mkOption { type = types.str; };
    credentialsFile = mkOption { type = types.str; };

    routes = mkOption {
      type = types.listOf routeType;
      default = [ ];
    };

    wildcardHostname = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    catchAll = mkOption {
      type = types.str;
      default = "http_status:404";
    };

    logLevel = mkOption {
      type = types.str;
      default = "info";
    };
  };

  config = mkIf cfg.enable {
    environment.etc."cloudflared/config.json".source = json.generate "cloudflared.json" configJson;

    systemd.services.cloudflared = {
      description = "Cloudflare Tunnel for Kubernetes services";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      aliases = [ "cloudflared-k8s.service" ];
      restartIfChanged = false;
      reloadIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        ExecStart = "${pkgs.cloudflared}/bin/cloudflared --config /etc/cloudflared/config.json tunnel run";
        Restart = "always";
        RestartSec = 10;
        User = "root";
        Group = "root";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/cloudflared" "/etc/cloudflared" ];
      };
    };
  };
}
