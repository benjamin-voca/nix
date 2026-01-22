{ config, pkgs, ... }:

{
  imports = [
    ../profiles/server.nix
    ../profiles/docker.nix
    # ../profiles/kubernetes/control-plane.nix
    ../services/gitea.nix
    # ../services/clickhouse.nix
    # ../services/otel.nix
  ];

  networking.firewall.allowedTCPPorts = [
    22 443 6443
  ];

  # services.kubernetes.roles = [ "master" ];
}
