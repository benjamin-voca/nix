{
  inputs,
  config,
  ...
}: let
  d = import ../../../lib/domain.nix;
  harborHost = d.host "harbor";
in {
  # containerd 2.2.1 fails to create containers from Android images
  # (redroid: /etc is an absolute symlink to /system/etc; Go 1.24 os.Root
  # rejects it -> "openat etc/passwd: path escapes from parent", fixed in
  # containerd >= 2.2.2, upstream #13382)
  nixpkgs.overlays = [
    (final: prev: {
      containerd = inputs.nixpkgs-containerd.legacyPackages.${prev.system}.containerd;
    })
  ];

  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
      plugins."io.containerd.grpc.v1.cri".registry.config_path = "/etc/containerd/certs.d";
      plugins."io.containerd.grpc.v1.cri".registry.configs.${harborHost}.tls.insecure_skip_verify = true;
    };
  };

  environment.etc."containerd/certs.d/${harborHost}/hosts.toml".text = ''
    server = "${d.url "harbor"}"

    [host."${d.url "harbor"}"]
      capabilities = ["pull", "resolve", "push"]
      skip_verify = true
  '';

  environment.etc."containerd/certs.d/10.0.0.56:5000/hosts.toml".text = ''
    server = "http://10.0.0.56:5000"

    [host."http://10.0.0.56:5000"]
      capabilities = ["pull", "resolve", "push"]
      skip_verify = true
  '';
}
