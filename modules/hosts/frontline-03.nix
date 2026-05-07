{config, ...}: {
  quad.hosts.frontline-03 = config.quad.lib.mkClusterHost {
    name = "frontline-03";
    system = "x86_64-linux";
    sshHost = "f1.quadtech.dev";
    hardwareModule = ../hardware/frontline-03.nix;
    roleModule = ../roles/frontline.nix;
    taints = [
      {
        key = "role";
        value = "frontline";
        effect = "NoSchedule";
      }
    ];
  };
}
