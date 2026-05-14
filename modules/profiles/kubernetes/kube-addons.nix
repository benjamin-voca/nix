{pkgs, ...}: {
  services.kubernetes = {};

  environment.systemPackages = with pkgs; [
    kubectl
  ];
}
