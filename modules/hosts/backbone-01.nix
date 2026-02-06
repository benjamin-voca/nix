{ config, ... }:

{
  quad.hosts.backbone-01 = config.quad.lib.mkClusterHost {
    name = "backbone-01";
    system = "x86_64-linux";
    hardwareModule = ../hardware/backbone-01.nix;
    roleModule = ../roles/backbone.nix;
  };
}
