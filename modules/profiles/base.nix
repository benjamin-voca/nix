{ config, pkgs, ... }:

{
  imports = [
    ../shared/quad-common.nix
    ./cachix.nix
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
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

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  services.cloudflared.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    helix
    ripgrep
    k9s
    envsubst
    sops
    htop
    curl
    cloudflared
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaEuHKb7PS/LyaBxvNzIcVzMOW0aDVHFnauM9pSjxm8 benjamin@Benjamins-MacBook-Pro.local"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINQisXyPG28p3bjlL6slxTsZWdQRDBcIq0eKf388kjJk klajdimac@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFikrtxTY3L49JN5OmWCFaNRAFBb6InjxPiXmc6iSCa2 gjonhajdari@chon-mekbuk.local"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDIjDVRgzc2UBRIbtwysmmW/F+zOjLm4PhmmKeYASoZK erti@DESKTOP-HLA1PQS"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINxZcBLleNnJ8BXX7+3jA3xROZjlz3C5dM76VTsy/sLh gashielion99@gmail.com"
  ];
}
