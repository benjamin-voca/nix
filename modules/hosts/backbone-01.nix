{config, ...}: {
  quad.hosts.backbone-01 = config.quad.lib.mkClusterHost {
    name = "backbone-01";
    system = "x86_64-linux";
    sshHost = "backbone01";
    remoteBuild = true;
    hardwareModule = ../hardware/backbone-01.nix;
    roleModule = ../roles/backbone.nix;
    extraModules = [
      ({lib, ...}: {
        boot.loader.grub.enable = lib.mkForce false;
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;
        boot.loader.efi.efiSysMountPoint = "/boot";
      })
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
