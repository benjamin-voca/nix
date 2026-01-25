{
  imports = [
    ./hardware.nix
    ../../roles/backbone.nix
    # ./systemd/cloudflared.nix  # Disabled - now using module in backbone.nix
  ];

  networking.hostName = "backbone-01";
}
