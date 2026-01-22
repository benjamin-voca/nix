{ config, lib, pkgs, ... }:

{
  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared --config /etc/cloudflared/config.yml tunnel run";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
