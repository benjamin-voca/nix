{
  imports = [
    ../../shared/quad-common.nix
    ../../shared/kubernetes-common.nix
    ../../kubernetes/worker.nix
  ];

  services.kubernetes = {
    enable = true;
    worker.enable = true;
  };
}
