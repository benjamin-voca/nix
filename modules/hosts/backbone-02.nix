{ config, ... }:

{
  quad.hosts.backbone-02 = config.quad.lib.mkClusterHost {
    name = "backbone-02";
    system = "x86_64-linux";
    hardwareModule = ../hardware/backbone-02.nix;
    roleModule = ../roles/backbone.nix;
  };
}
