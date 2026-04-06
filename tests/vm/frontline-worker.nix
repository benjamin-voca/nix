{ lib, pkgs }:

pkgs.testers.nixosTest {
  name = "quadnix-vm-frontline-worker";

  nodes = {
    backbone = {
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

    worker = {
      imports = [
        ../../modules/profiles/base.nix
        ../../modules/profiles/server.nix
        ../../modules/profiles/docker.nix
        ../../modules/profiles/kubernetes/worker.nix
      ];

      networking = {
        hostName = "frontline";
        domain = "test";
        firewall.enable = lib.mkForce false;
      };

      services.kubernetes = {
        masterAddress = lib.mkForce "backbone.test";
      };

      virtualisation = {
        memorySize = 3072;
        cores = 2;
      };
    };
  };

  testScript = ''
    start_all()

    backbone.wait_for_unit("kube-apiserver.service")
    worker.wait_for_unit("containerd.service")
    worker.wait_for_unit("kubelet.service")

    worker.wait_until_succeeds(
      "systemctl is-active kubelet.service"
    )
    worker.wait_until_succeeds(
      "test -f /etc/containerd/certs.d/harbor.quadtech.dev/hosts.toml"
    )
    worker.wait_until_succeeds(
      "grep -q 'server = \"https://harbor.quadtech.dev\"' /etc/containerd/certs.d/harbor.quadtech.dev/hosts.toml"
    )
  '';
}
