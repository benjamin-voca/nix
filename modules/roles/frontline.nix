{lib, ...}: {
  imports = [
    ../profiles/base.nix
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/worker.nix
  ];

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
    extraServiceSettings = {
      server = {
        allow-interfaces = "enp3s0";
      };
    };
  };

  virtualisation.docker.autoPrune.enable = lib.mkForce false;

  systemd.services.docker-prune =
    lib.mkForce
    {
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
