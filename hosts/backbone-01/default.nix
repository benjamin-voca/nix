{
  imports = [
    ./hardware.nix
    ../../roles/backbone.nix
    ./systemd/cloudflared.nix
  ];

  networking.hostName = "backbone-01";
}
