{
  config,
  lib,
  pkgs,
  ...
}: {
  # Tailscale as subnet router - exposes LAN to your tailnet
  # kubectl on macOS will connect via Tailscale IP (100.x.x.x) instead of SSH tunnel
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server"; # subnet router + relay
    authKeyFile = "/run/secrets/tailscale-auth-key";
  };

  # Allow Tailscale through firewall
  networking.firewall.allowedUDPPorts = [41641];

  # ------------------------------------------------------------------ #
  # Auto-restart: keep tailscaled alive at all costs.                   #
  # The upstream unit uses Restart=on-failure plus a start-limit, which #
  # gives up after a burst of restarts and never recovers a process     #
  # that exits "cleanly". We restart unconditionally and disable the    #
  # start-limit so systemd keeps trying forever (same pattern as the    #
  # cloudflared service in roles/backbone.nix).                         #
  # ------------------------------------------------------------------ #
  systemd.services.tailscaled = {
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
    unitConfig = {
      StartLimitIntervalSec = "0"; # never stop retrying
    };
  };

  # ------------------------------------------------------------------ #
  # Watchdog: catch a daemon that is alive but wedged.                  #
  # Restart=always only fires when the process exits. If tailscaled     #
  # keeps running but BackendState is stuck in Stopped/NeedsLogin (the  #
  # "lost access overnight" failure mode), the process never dies and   #
  # nothing recovers it. This oneshot polls the daemon every 5 min and  #
  # restarts it when it stops answering `tailscale status` or leaves    #
  # the Running state.                                                  #
  # ------------------------------------------------------------------ #
  systemd.services.tailscale-watchdog = {
    description = "Restart tailscaled if it is unresponsive or not running";
    after = ["network-online.target" "tailscaled.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    path = with pkgs; [tailscale jq coreutils systemd];
    script = ''
      set -o pipefail
      # Probe the local daemon; a healthy tailscaled answers in well under a second.
      state=$(timeout 10 tailscale status --json --peers=false 2>/dev/null \
              | jq -r '.BackendState // "Unknown"') || state="Unknown"
      echo "tailscale BackendState=$state"
      if [ "$state" != "Running" ]; then
        echo "tailscaled unhealthy (BackendState=$state) - restarting tailscaled"
        systemctl restart tailscaled
      fi
    '';
  };

  systemd.timers.tailscale-watchdog = {
    description = "Periodic tailscale health check";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min"; # let tailscaled settle after boot before first check
      OnUnitActiveSec = "5min";
      AccuracySec = "30s";
      Persistent = true;
    };
  };
}
