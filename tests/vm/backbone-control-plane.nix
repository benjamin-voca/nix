{
  lib,
  pkgs,
}:
pkgs.testers.nixosTest {
  name = "quadnix-vm-backbone-control-plane";

  nodes.backbone = {
    pkgs,
    lib,
    ...
  }: {
    imports = [
      ../../modules/profiles/base.nix
      ../../modules/profiles/server.nix
      ../../modules/profiles/docker.nix
      ../../modules/profiles/kubernetes/control-plane.nix
    ];

    networking = {
      hostName = "backbone";
      domain = "test";
      firewall.enable = lib.mkForce false;
    };

    services.kubernetes = {
      masterAddress = lib.mkForce "backbone.test";
      apiserverAddress = lib.mkForce "https://127.0.0.1:6443";
    };

    systemd.services.flannel.serviceConfig.ExecStart = lib.mkOverride 0 ''
      ${pkgs.flannel}/bin/flannel \
        -etcd-endpoints=https://127.0.0.1:2379 \
        -etcd-cafile=/var/lib/kubernetes/secrets/ca.pem \
        -etcd-certfile=/var/lib/kubernetes/secrets/kubernetes.pem \
        -etcd-keyfile=/var/lib/kubernetes/secrets/kubernetes-key.pem \
        -kubeconfig-file=/etc/kubernetes/cluster-admin.kubeconfig \
        -v=10
    '';

    virtualisation = {
      memorySize = 4096;
      cores = 2;
    };
  };

  testScript = ''
    start_all()

    backbone.wait_for_unit("containerd.service")
    backbone.wait_for_unit("etcd.service")
    backbone.wait_for_unit("kube-apiserver.service")
    backbone.wait_for_unit("flannel.service")

    backbone.wait_until_succeeds(
      "KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig kubectl get --raw=/healthz | grep -q ok"
    )
    backbone.wait_until_succeeds(
      "KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig kubectl get nodes -o name | grep -q node/backbone"
    )
  '';
}
