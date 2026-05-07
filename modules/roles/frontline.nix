{lib, ...}: {
  imports = [
    ../profiles/base.nix
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/worker.nix
  ];

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
