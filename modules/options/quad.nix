{ lib, ... }:

{
  options.quad = {
    hosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = {};
      description = "Evaluated NixOS configurations keyed by host name.";
    };

    lib = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Quad helper library exposed to all modules.";
    };
  };
}
