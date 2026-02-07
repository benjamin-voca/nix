{ config, pkgs, lib, ... }:

{
  imports = [
    ../profiles/base.nix
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/sops.nix
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/allow-master-workloads.nix
    ../profiles/kubernetes/helm.nix
    ../services/cloudflared-k8s-deploy.nix
  ];

  services.openiscsi = {
    enable = true;
    name = "iqn.2004-10.org.debian:${config.networking.hostName}";
  };

  systemd.tmpfiles.rules = [
    "L+ /usr/bin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
    "L+ /usr/sbin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
  ];

  networking.firewall.allowedTCPPorts = [
    22 443 6443
  ];

  sops.secrets = {
    cloudflared-credentials = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/cloudflared-credentials.json";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    gitea-db-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    };
    infisical-db-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    };
    infisical-encryption-key = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    };
    infisical-auth-secret = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    };
  };

  services.cloudflared-k8s-deploy = {
    enable = true;
    tunnelId = "b6bac523-be70-4625-8b67-fa78a9e1c7a5";
    replicas = 1;
    imageTag = "2025.2.0";
  };
}
