{ config, lib, ... }:

{
  # Cachix binary cache configuration
  # This provides declarative configuration for Cachix caches
  
  nix.settings = {
    # Binary cache substituters
    substituters = [
      "https://cache.nixos.org"
      "https://nixhelm.cachix.org"
      "https://nix-community.cachix.org"
    ];

    # Trusted public keys for the caches
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

    # Allow downloading pre-built binaries from these caches
    trusted-substituters = [
      "https://cache.nixos.org"
      "https://nixhelm.cachix.org"
      "https://nix-community.cachix.org"
    ];
  };
}
