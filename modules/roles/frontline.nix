{lib, ...}: {
  imports = [
    ../profiles/base.nix
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/worker.nix
  ];

  systemd.services.docker-prune = {
    script = "docker system prune -af";
    startAt = lib.mkForce ["daily"];
    wantedBy = ["multi-user.target"];
  };
}
