{
  description = "Test flake";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.test = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ({ pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; }) ];
    };
  };
}
