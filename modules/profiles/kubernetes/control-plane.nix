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
    ./containerd-registry.nix
    ./pki-renew.nix
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
    apiserver.extraSANs = [
      config.networking.hostName
      config.networking.fqdn
      "localhost"
      "127.0.0.1"
      "kubernetes.quadtech.dev"
      # Tailscale - access via https://100.x.x.x:6443 (static Tailscale IP) or https://backbone-01.tailf26317.ts.net:6443 (MagicDNS)
      "100.100.145.110"
      "${config.networking.hostName}.tailf26317.ts.net"
      "${config.networking.hostName}.tail-scale.ts.net"
    ];
    apiserver.extraOpts = "--allow-privileged=true";
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


  # Override the upstream kubernetes module's cfssl signing profile to
  # issue 1-year certs (upstream default is 30 days). This is consulted
  # by anything that talks to the cfssl HTTP API (e.g. workers joining
  # the cluster). Our on-disk renewal script uses its own signing config
  # with the same expiry.
  services.cfssl.configFile = lib.mkForce (toString (
    pkgs.writeText "cfssl-config.json" (
      builtins.toJSON {
        signing = {
          profiles = {
            default = {
              usages = ["digital signature" "key encipherment" "server auth" "client auth"];
              auth_key = "default";
              expiry = "8760h"; # 1 year
            };
          };
        };
        auth_keys = {
          default = {
            type = "standard";
            key = "file:${config.services.cfssl.dataDir}/apitoken.secret";
          };
        };
      }
    )
  ));

  # Replace certmgr with our pki-renew module. certmgr v3.0.3 has a bug
  # that causes it to restart the entire control plane every renewInterval
  # cycle; pki-renew only restarts when certificates are actually close
  # to expiry. See ./pki-renew.nix for the full rationale.
  services.kubernetes.pkiRenew = {
    enable = true;
    renewBeforeDays = 30;
    interval = "1h";
  };

  # Ordering: kube-pki-renew runs after cfssl and before the k8s control
  # plane so first-boot generation completes before apiserver tries to
  # read its cert. Soft `wants` (not `requires`) so a renewal failure
  # doesn't tear down a running cluster — the on-disk certs remain.
  systemd.services.etcd = {
    after = ["cfssl.service" "kube-pki-renew.service" "network-online.target"];
    wants = ["cfssl.service" "kube-pki-renew.service"];
  };

  systemd.services.kube-apiserver = {
    after = ["cfssl.service" "kube-pki-renew.service" "etcd.service"];
    wants = ["cfssl.service" "kube-pki-renew.service"];
    requires = ["etcd.service"];
    environment.GODEBUG = "netdns=cgo";
  };

  systemd.services.kubelet.environment.GODEBUG = "netdns=cgo";
  systemd.services.kube-proxy.environment.GODEBUG = "netdns=cgo";

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
