{
  imports = [
    ../../shared/quad-common.nix
    ../../shared/kubernetes-common.nix
    ../../kubernetes/control-plane.nix
  ];

  services.kubernetes.controlPlane = {
    enable = true;
    etcd.enable = true;
    apiServer.enable = true;
    scheduler.enable = true;
    controllerManager.enable = true;
  };
}
