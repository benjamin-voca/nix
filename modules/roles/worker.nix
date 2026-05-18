{lib, pkgs, ...}: {
  imports = [
    ../profiles/base.nix
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/worker.nix
  ];

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    interfaces = ["enp3s0"];
    publish = {
      enable = true;
      addresses = true;
    };
  };

  services.resolved = {
    enable = true;
    settings.Resolve.MulticastDNS = "yes";
  };

  virtualisation.docker.autoPrune.enable = lib.mkForce false;

  systemd.services.docker-prune =
    lib.mkForce
    {
      path = [pkgs.docker];
      script = "docker system prune -af";
      startAt = "daily";
      wantedBy = ["multi-user.target"];
      serviceConfig.Type = "oneshot";
    };

  systemd.timers.docker-prune =
    lib.mkForce
    {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
}
