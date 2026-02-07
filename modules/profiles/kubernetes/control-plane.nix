{ config, lib, pkgs, ... }:

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
    roles = [ "master" "node" ];
    masterAddress = config.networking.fqdn;
    easyCerts = true;
    caFile = "/var/lib/kubernetes/secrets/ca.pem";
    pki.cfsslAPIExtraSANs = [
      config.networking.hostName
      config.networking.fqdn
    ];
    apiserver.extraOpts = "--allow-privileged=true";
  };


  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
    };
  };

  systemd.services.certmgr = {
    after = [ "cfssl.service" "network-online.target" ];
    wants = [ "cfssl.service" "network-online.target" ];
    serviceConfig = {
      ExecStartPre = [
        "${pkgs.bash}/bin/sh -c 'for i in $(seq 1 60); do ${pkgs.netcat}/bin/nc -z 127.0.0.1 8888 && exit 0; sleep 1; done; exit 1'"
      ];
    };
  };

  systemd.services.etcd = {
    after = [ "certmgr.service" ];
    requires = [ "certmgr.service" ];
  };

  systemd.services.kube-apiserver = {
    after = [ "certmgr.service" "etcd.service" ];
    requires = [ "certmgr.service" "etcd.service" ];
  };

  systemd.services.flannel = {
    after = [ "kube-apiserver.service" "network-online.target" ];
    wants = [ "kube-apiserver.service" "network-online.target" ];
    requires = [ "kube-apiserver.service" ];
    serviceConfig.ExecStartPre = lib.mkBefore [
      "${pkgs.bash}/bin/sh -c 'for i in $(seq 1 90); do ${pkgs.curl}/bin/curl -fsSk https://127.0.0.1:6443/healthz >/dev/null && exit 0; sleep 1; done; exit 1'"
    ];
  };

  systemd.services.kube-addon-manager = {
    after = [ "kube-apiserver.service" "network-online.target" ];
    wants = [ "kube-apiserver.service" "network-online.target" ];
    requires = [ "kube-apiserver.service" ];
    serviceConfig.ExecStartPre = lib.mkBefore [
      "${pkgs.bash}/bin/sh -c 'for i in $(seq 1 90); do ${pkgs.curl}/bin/curl -fsSk https://127.0.0.1:6443/healthz >/dev/null && exit 0; sleep 1; done; exit 1'"
    ];
  };
}
