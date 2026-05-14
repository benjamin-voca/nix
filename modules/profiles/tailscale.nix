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
    useRoutingFeatures = "server";  # subnet router + relay
    authKeyFile = "/run/secrets/tailscale-auth-key";
  };

  # Allow Tailscale through firewall
  networking.firewall.allowedUDPPorts = [ 41641 ];
}