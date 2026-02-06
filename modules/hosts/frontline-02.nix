{ config, ... }:

{
  quad.hosts.frontline-02 = config.quad.lib.mkClusterHost {
    name = "frontline-02";
    system = "x86_64-linux";
    hardwareModule = ../hardware/frontline-02.nix;
    roleModule = ../roles/frontline.nix;
  };
}
