{pkgs, ...}: {
  imports = [
    ../shared/quad-common.nix
    ./cachix.nix
  ];

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    auto-optimise-store = true;
    substituters = [
      "https://cache.nixos.org"
      "https://nixhelm.cachix.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  time.timeZone = "UTC";
  networking.firewall.enable = true;

  # Upstream nixpkgs defaults DefaultIPAccounting=true, which makes systemd
  # attach its sd_fw_{ingress,egress} BPF programs (BPF_F_ALLOW_MULTI) to
  # every cgroup on the host. Ancestor multi-attached programs make ALL
  # exclusive cgroup BPF attaches fail with EPERM — which crash-loops
  # Android/redroid netd at boot (libnetd_updatable_init). No consumer of
  # these counters; off it goes. See runbooks/android-fleet.md.
  systemd.settings.Manager.DefaultIPAccounting = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  # services.cloudflared.enable = true;  # Disabled - using custom systemd service in backbone.nix

  environment.systemPackages = with pkgs; [
    vim
    git
    helix
    ripgrep
    k9s
    sops
    htop
    curl
    cloudflared
    jq
    yq
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaEuHKb7PS/LyaBxvNzIcVzMOW0aDVHFnauM9pSjxm8 benjamin@Benjamins-MacBook-Pro.local"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINQisXyPG28p3bjlL6slxTsZWdQRDBcIq0eKf388kjJk klajdimac@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDIjDVRgzc2UBRIbtwysmmW/F+zOjLm4PhmmKeYASoZK erti@DESKTOP-HLA1PQS"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINxZcBLleNnJ8BXX7+3jA3xROZjlz3C5dM76VTsy/sLh gashielion99@gmail.com"
  ];
}
