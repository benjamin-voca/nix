{
  nix.settings = {
    substituters = [
      "https://nixhelm.cachix.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
