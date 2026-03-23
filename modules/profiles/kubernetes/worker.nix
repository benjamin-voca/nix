{ config, pkgs, ... }:

{
  imports = [
    ../../shared/quad-common.nix
  ];

  environment.systemPackages = with pkgs; [
    kubernetes
    kubectl
    cri-tools
    containerd
  ];

  services.kubernetes = {
    roles = [ "node" ];
  };

  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
      plugins."io.containerd.grpc.v1.cri".registry.config_path = "/etc/containerd/certs.d";
      plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.quadtech.dev".tls.insecure_skip_verify = true;
    };
  };

  environment.etc."containerd/certs.d/10.0.0.56:5000/hosts.toml".text = ''
    server = "http://10.0.0.56:5000"

    [host."http://10.0.0.56:5000"]
      capabilities = ["pull", "resolve", "push"]
      skip_verify = true
  '';
}
