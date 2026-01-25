{ config, pkgs, ... }:

{
  imports = [
    ./cachix.nix
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
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
