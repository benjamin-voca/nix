{
  config,
  lib,
  pkgs,
  ...
}: let
  flannelInterface = "enp0s31f6";
in {
  imports = [
    ../../shared/quad-common.nix
  ];

  boot.kernelModules = [
    "nfs"
    "nfsv4"
    "nfsv4_1"
    "nfsv4_2"
    "vfio_pci"
    "uio_pci_generic"
    "nvme-tcp"
  ];

  boot.extraModulePackages = with config.boot.kernelPackages; [
  ];

  boot.kernelParams = [
    "hugepagesz=2M"
    "hugepages=1024"
  ];

  environment.systemPackages = with pkgs; [
    kubernetes
    kubectl
    cri-tools
    containerd
    flannel
  ];

  services.kubernetes = {
    roles = ["master" "node"];
    masterAddress = config.networking.fqdn;
    easyCerts = true;
    caFile = "/var/lib/kubernetes/secrets/ca.pem";
    pki.cfsslAPIExtraSANs = [
      config.networking.hostName
      config.networking.fqdn
      "localhost"
      "127.0.0.1"
      "kubernetes.quadtech.dev"
    ];
    apiserver.extraOpts = "--allow-privileged=true";
    # Global CPU overprovisioning: allow scheduling up to 200% CPU utilization
    scheduler.extraOpts = "--percentage-of-nodes-to-score=200";
    # K8s 1.27+ rejects kubernetes.io/* labels via --node-labels flag.
    # Set role labels through the kubelet config file instead.
    kubelet.extraOpts = "--node-labels=node.kubernetes.io/instance-type=standard";
    kubelet.extraConfig = {
      evictionHard = {
        "memory.available" = "1%";
        "nodefs.available" = "1%";
        "imagefs.available" = "1%";
      };
      evictionSoft = {
        "memory.available" = "2%";
        "nodefs.available" = "2%";
        "imagefs.available" = "2%";
      };
      evictionSoftGracePeriod = {
        "memory.available" = "2m";
        "nodefs.available" = "2m";
        "imagefs.available" = "2m";
      };
      evictionMinimumGracePeriod = "30s";
      # Allow more CPU to be scheduled (overprovisioning)
      systemReserved = {
        cpu = "500m";
        memory = "1Gi";
      };
      kubeReserved = {
        cpu = "500m";
        memory = "1Gi";
      };
      nodeLabels = {
        "node-role.kubernetes.io/control-plane" = "";
        "node-role.kubernetes.io/node" = "";
      };
    };
    # CoreDNS: forward external queries to public DNS (not router)
    addons.dns.corefile = ''
      .:10053 {
        errors
        health :10054
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :10055
        forward . 8.8.8.8 1.1.1.1
        cache 30
        loop
        reload
        loadbalance
      }
    '';
  };

  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
      plugins."io.containerd.grpc.v1.cri".registry.config_path = "/etc/containerd/certs.d";
      plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.quadtech.dev".tls.insecure_skip_verify = true;
    };
  };

  environment.etc."containerd/certs.d/harbor.quadtech.dev/hosts.toml".text = ''
    server = "https://harbor.quadtech.dev"

    [host."https://harbor.quadtech.dev"]
      capabilities = ["pull", "resolve", "push"]
      skip_verify = true
  '';

  environment.etc."containerd/certs.d/10.0.0.56:5000/hosts.toml".text = ''
    server = "http://10.0.0.56:5000"

    [host."http://10.0.0.56:5000"]
      capabilities = ["pull", "resolve", "push"]
      skip_verify = true
  '';

  systemd.services.certmgr = {
    after = ["cfssl.service" "network-online.target"];
    wants = ["cfssl.service" "network-online.target"];
    serviceConfig = {
      ExecStartPre = [
        "${pkgs.bash}/bin/sh -c 'for i in $(seq 1 60); do ${pkgs.netcat}/bin/nc -z 127.0.0.1 8888 && exit 0; sleep 1; done; exit 1'"
      ];
    };
  };

  systemd.services.etcd = {
    after = ["certmgr.service"];
    requires = ["certmgr.service"];
  };

  systemd.services.kube-apiserver = {
    after = ["certmgr.service" "etcd.service"];
    requires = ["certmgr.service" "etcd.service"];
  };

  systemd.services.flannel = {
    after = ["kube-apiserver.service" "etcd.service" "network-online.target"];
    wants = ["kube-apiserver.service" "network-online.target"];
    requires = ["kube-apiserver.service" "etcd.service"];
    serviceConfig = {
      ExecStartPre = lib.mkBefore [
        "${pkgs.bash}/bin/sh -c 'for i in $(seq 1 120); do ${pkgs.curl}/bin/curl -fsSk https://127.0.0.1:6443/healthz >/dev/null && exit 0; sleep 1; done; exit 1'"
        "${pkgs.bash}/bin/sh -c 'export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig; ${pkgs.kubectl}/bin/kubectl create clusterrolebinding flannel-crb --clusterrole=system:flannel --serviceaccount=kube-system:flannel --dry-run=client -o yaml | ${pkgs.kubectl}/bin/kubectl apply -f - 2>/dev/null || true'"
      ];
      ExecStart = lib.mkForce "${pkgs.flannel}/bin/flannel -etcd-endpoints=https://127.0.0.1:2379 -etcd-cafile=/var/lib/kubernetes/secrets/ca.pem -etcd-certfile=/var/lib/kubernetes/secrets/kubernetes.pem -etcd-keyfile=/var/lib/kubernetes/secrets/kubernetes-key.pem -kubeconfig-file=/etc/kubernetes/cluster-admin.kubeconfig -iface=${flannelInterface} -v=10";
      Restart = lib.mkForce "on-failure";
    };
  };

  systemd.services.kube-addon-manager = {
    after = ["kube-apiserver.service" "network-online.target"];
    wants = ["kube-apiserver.service" "network-online.target"];
    requires = ["kube-apiserver.service"];
    serviceConfig.ExecStartPre = lib.mkBefore [
      "${pkgs.bash}/bin/sh -c 'for i in $(seq 1 90); do ${pkgs.curl}/bin/curl -fsSk https://127.0.0.1:6443/healthz >/dev/null && exit 0; sleep 1; done; exit 1'"
    ];
  };
}
