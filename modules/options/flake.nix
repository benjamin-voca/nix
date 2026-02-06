{ lib, ... }:

{
  options.flake = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = "Flake outputs assembled by top-level modules.";
  };
}
