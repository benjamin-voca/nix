{ config, ... }:

{
  quad.hosts.frontline-01 = config.quad.lib.mkClusterHost {
    name = "frontline-01";
    system = "x86_64-linux";
    hardwareModule = ../hardware/frontline-01.nix;
    roleModule = ../roles/frontline.nix;
  };
}
