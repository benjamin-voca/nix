{
  description = "QuadNix NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs = { self, nixpkgs, sops-nix, deploy-rs, ... }: {
    nixosConfigurations = {
      backbone-01 = (import ./lib/mkHost.nix { inherit nixpkgs; })
        "backbone-01" "x86_64-linux";

      backbone-02 = (import ./lib/mkHost.nix { inherit nixpkgs; })
        "backbone-02" "x86_64-linux";

      frontline-01 = (import ./lib/mkHost.nix { inherit nixpkgs; })
        "frontline-01" "x86_64-linux";

      frontline-02 = (import ./lib/mkHost.nix { inherit nixpkgs; })
        "frontline-02" "x86_64-linux";
    };

    deploy = {
      nodes = {
        "backbone-01" = {
          hostname = "192.168.1.10";
          profiles = {
            system = "./result";
          };
          sshUser = "root";
        };

        "backbone-02" = {
          hostname = "192.168.1.11";
          profiles = {
            system = "./result";
          };
          sshUser = "root";
        };

        "frontline-01" = {
          hostname = "192.168.1.20";
          profiles = {
            system = "./result";
          };
          sshUser = "root";
        };

        "frontline-02" = {
          hostname = "192.168.1.21";
          profiles = {
            system = "./result";
          };
          sshUser = "root";
        };
      };
    };
  };
}
