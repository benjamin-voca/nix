{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../../shared/quad-common.nix
    ./containerd-registry.nix
  ];

  environment.systemPackages = with pkgs; [
    kubernetes
    kubectl
    cri-tools
    containerd
  ];

  services.kubernetes = {
    roles = ["node"];
    masterAddress = lib.mkDefault "backbone-01.local";
  };

  systemd.services.kubelet.environment.GODEBUG = "netdns=cgo";
  systemd.services.kube-proxy.environment.GODEBUG = "netdns=cgo";
}
