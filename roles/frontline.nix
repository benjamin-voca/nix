{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/kubernetes/worker.nix
  ];

  services.kubernetes.roles = [ "node" ];

  systemd.services.docker-prune = {
    script = "docker system prune -af";
    startAt = "daily";
    wantedBy = [ "multi-user.target" ];
  };
}
