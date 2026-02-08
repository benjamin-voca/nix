{ config, inputs, lib, ... }:

{
  options.test.option = lib.mkOption { type = lib.types.str; };
  config = {
    test.option = "test-value";
    flake.nixosConfigurations = {
      test = lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ({ pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; })
          ({ config, ... }: {
            test.option = "overridden-value";
          })
        ];
      };
    };
  };
}
