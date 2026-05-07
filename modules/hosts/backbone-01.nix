{config, ...}: {
  quad.hosts.backbone-01 = config.quad.lib.mkClusterHost {
    name = "backbone-01";
    system = "x86_64-linux";
    sshHost = "mainssh.quadtech.dev";
    remoteBuild = true;
    hardwareModule = ../hardware/backbone-01.nix;
    roleModule = ../roles/backbone.nix;
    extraModules = [
    ];
    taints = [
      {
        key = "role";
        value = "backbone";
        effect = "NoSchedule";
      }
      {
        key = "infra";
        value = "true";
        effect = "NoSchedule";
      }
    ];
  };
}
