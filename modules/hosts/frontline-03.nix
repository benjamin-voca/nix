{config, ...}: {
  quad.hosts.frontline-03 = config.quad.lib.mkClusterHost {
    name = "frontline-03";
    system = "x86_64-linux";
    sshHost = "192.168.1.15";
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
