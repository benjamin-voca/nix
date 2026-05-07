{lib, ...}: {
  imports = [
    ../profiles/base.nix
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/worker.nix
  ];

  networking.hosts."192.168.1.10" = ["backbone-01.local"];

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
