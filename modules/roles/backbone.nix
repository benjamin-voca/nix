{ config, pkgs, ... }:

{
  imports = [
    ../profiles/base.nix
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/sops.nix
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/allow-master-workloads.nix
    ../services/argocd-deploy.nix
    ../services/helm-charts.nix
    ../services/verdaccio-deploy.nix
    ../services/infiscal-deploy.nix
    ../services/argocd-apps.nix
    ../gitea/runner.nix
  ];

  environment.systemPackages = with pkgs; [
    nfs-utils
    apacheHttpd  # For htpasswd utility
    openssl
  ];

  services.openiscsi = {
    enable = true;
    name = "iqn.2004-10.org.debian:${config.networking.hostName}";
  };

  systemd.tmpfiles.rules = [
    "L+ /usr/bin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
    "L+ /usr/sbin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
    "d /usr/local - - - -"
    "d /usr/local/sbin - - - -"
    "d /usr/local/bin - - - -"
  ];

  environment.etc."local/sbin/nsmounter".text = ''
    #!/bin/bash
    # NixOS-compatible nsmounter - use container mount.nfs for NFS mounts

    # If this is an NFS mount, convert standard mount args to mount.nfs format
    if [[ "$*" == *"-t nfs"* ]] || [[ "$*" == *"nfs"* ]]; then
        # Skip the "mount" command if present
        if [[ "$1" == "mount" ]]; then
            shift
        fi

        # Extract the NFS remote (e.g., 10.0.0.88:/pvc-xxx), mountpoint, and options
        REMOTE=""
        MOUNTPOINT=""
        OPTIONS=""

        # Parse arguments
        while [[ $# -gt 0 ]]; do
            case $1 in
                -t)
                    shift 2  # skip -t nfs
                    ;;
                -o)
                    OPTIONS="$2"
                    shift 2
                    ;;
                *)
                    if [[ -z "$REMOTE" ]]; then
                        REMOTE="$1"
                    elif [[ -z "$MOUNTPOINT" ]]; then
                        MOUNTPOINT="$1"
                    fi
                    shift
                    ;;
            esac
        done

        # Resolve service IP to pod IP
        SERVER="''${REMOTE%%:*}"
        EXPORT="''${REMOTE#*:}"

        # If server is a service IP (10.x.x.x), try to resolve
        if [[ "$SERVER" =~ ^10\. ]]; then
            # Try using getent
            ENDPOINT_IP=$(getent hosts "$SERVER" 2>/dev/null)
            if [ -z "$ENDPOINT_IP" ]; then
                # Try using nsenter to check DNS resolution
                ENDPOINT_IP=$(nsenter -t 1 -n -- getent hosts "$SERVER" 2>/dev/null)
            fi
            if [ -n "$ENDPOINT_IP" ]; then
                # Extract IP from getent output (format: "IP hostname")
                SERVER=''${ENDPOINT_IP%% *}
            fi
        fi

        REMOTE="$SERVER:$EXPORT"

        # Call mount.nfs with converted args - use /host/usr/local for mount.nfs
        exec /host/usr/local/bin/mount.nfs "$REMOTE" "$MOUNTPOINT" -o "$OPTIONS"
    fi

    # Otherwise use regular mount
    exec /run/current-system/sw/bin/mount "$@"
  '';

  environment.etc."local/bin/mount.nfs".source = "${pkgs.nfs-utils}/sbin/mount.nfs";

  systemd.services.longhorn-nsmounter = {
    description = "Deploy nsmounter for Longhorn CSI";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    script = ''
      # Ensure directories exist
      mkdir -p /usr/local/sbin /usr/local/bin

      # Copy nsmounter from Nix store
      if [ -f /etc/local/sbin/nsmounter ]; then
        cp /etc/local/sbin/nsmounter /usr/local/sbin/nsmounter
        chmod +x /usr/local/sbin/nsmounter
      fi

      # Copy mount.nfs from Nix store
      if [ -f /etc/local/bin/mount.nfs ]; then
        cp /etc/local/bin/mount.nfs /usr/local/bin/mount.nfs
        chmod +x /usr/local/bin/mount.nfs
      fi

      # Patch Longhorn CSI plugin DaemonSet to include /host/usr/local mount
      if [ -f /var/lib/kubernetes/admin.kubeconfig ]; then
        export KUBECONFIG=/var/lib/kubernetes/admin.kubeconfig
        
        # Check if the volumeMount already exists
        if ! kubectl get ds longhorn-csi-plugin -n longhorn-system -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}' 2>/dev/null | grep -q "/host/usr/local"; then
          # Add the host-usr-local volume if it doesn't exist
          if kubectl get ds longhorn-csi-plugin -n longhorn-system -o jsonpath='{.spec.template.spec.volumes[*].name}' 2>/dev/null | grep -q "host-usr-local"; then
            kubectl patch daemonset longhorn-csi-plugin -n longhorn-system --type="json" -p='[{"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "host-usr-local", "mountPath": "/host/usr/local"}}]' 2>/dev/null || true
          else
            # Add both volume and volumeMount
            kubectl patch daemonset longhorn-csi-plugin -n longhorn-system --type="json" -p='[{"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "host-usr-local", "hostPath": {"path": "/usr/local", "type": "Directory"}}}, {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "host-usr-local", "mountPath": "/host/usr/local"}}]' 2>/dev/null || true
          fi
        fi
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  networking.firewall.allowedTCPPorts = [
    22 443 6443
  ];

    sops.secrets = {
      cloudflared-credentials = {
        sopsFile = ../../secrets/${config.networking.hostName}.yaml;
        path = "/run/secrets/cloudflared-credentials.json";
        owner = "root";
        group = "root";
        mode = "0400";
      };
      gitea-db-password = {
        sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      };
      infisical-db-password = {
        sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      };
      infisical-encryption-key = {
        sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      };
      infisical-auth-secret = {
        sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      };
      argocd-admin-password = {
        sopsFile = ../../secrets/${config.networking.hostName}.yaml;
        path = "/run/secrets/argocd-admin-password";
        owner = "root";
        group = "root";
        mode = "0400";
      };
      gitea-runner-token = {
        sopsFile = ../../secrets/${config.networking.hostName}.yaml;
        path = "/run/secrets/gitea-runner-token";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };

  services.quadnix.argocd-deploy = {
    enable = true;
  };

   services.quadnix.infisical-deploy = {
     enable = true;
   };

   services.quadnix.verdaccio-deploy = {
     enable = true;
   };

  services.quadnix.argocdApps = {
    enable = true;
    harbor = true;
    verdaccio = true;
  };

  # Gitea Actions Runners
  services.gitea.runner = {
    enable = true;
    instanceName = "backbone-runner-1";
    tokenFile = "/run/secrets/gitea-runner-token";
    labels = [ "ubuntu-latest" "linux" "x86_64" "self-hosted" ];
  };

  # Cloudflared tunnel service (runs on host for SSH access via Cloudflare Tunnel)
  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --protocol http2 --config /etc/cloudflared/config/config.yaml run";
      Restart = "always";
      RestartSec = "10s";
      User = "root";
    };
  };

  # Create cloudflared config directory and files
  systemd.services.cloudflared.preStart = ''
    mkdir -p /etc/cloudflared/config /etc/cloudflared/creds
    
    # Write cloudflared config
    cat > /etc/cloudflared/config/config.yaml << 'EOF'
tunnel: b6bac523-be70-4625-8b67-fa78a9e1c7a5
credentials-file: /etc/cloudflared/creds/credentials.json
protocol: http2
metrics: 0.0.0.0:2000
no-autoupdate: true
ingress:
  - hostname: backbone-01.quadtech.dev
    service: ssh://localhost:22
  - hostname: gitea-ssh.quadtech.dev
    service: tcp://192.168.1.240:32222
  - hostname: gitea.quadtech.dev
    service: http://192.168.1.240:80
  - hostname: argocd.quadtech.dev
    service: http://192.168.1.240:80
  - hostname: harbor.quadtech.dev
    service: http://192.168.1.240:80
  - service: http_status:404
EOF
    
    # Copy credentials from SOPS secret
    cp /run/secrets/cloudflared-credentials.json /etc/cloudflared/creds/credentials.json
    chmod 600 /etc/cloudflared/creds/credentials.json
  '';

  # Enable 2 additional runners via systemd service instances
  systemd.services.gitea-runner-2 = {
    description = "Gitea actions runner 2";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.gitea-actions-runner}/bin/act_runner daemon --config /etc/gitea/runner/config-2.yaml";
      Restart = "always";
      StateDirectory = "gitea-runner-2";
      WorkingDirectory = "/var/lib/gitea-runner-2";
    };
  };

  systemd.services.gitea-runner-3 = {
    description = "Gitea actions runner 3";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.gitea-actions-runner}/bin/act_runner daemon --config /etc/gitea/runner/config-3.yaml";
      Restart = "always";
      StateDirectory = "gitea-runner-3";
      WorkingDirectory = "/var/lib/gitea-runner-3";
    };
  };

  # Create config files for additional runners (token read from file at runtime via systemd service)
  systemd.services.gitea-runner-2.preStart = ''
    mkdir -p /etc/gitea/runner /var/lib/gitea-runner-2
    cat > /etc/gitea/runner/config-2.yaml << EOF
runner:
  name: backbone-runner-2
  labels:
    - ubuntu-latest
    - linux
    - x86_64
    - self-hosted
  token: $(cat /run/secrets/gitea-runner-token)
  url: https://gitea.quadtech.dev
  state_dir: /var/lib/gitea-runner-2
EOF
    # Register runner if not already registered
    if [ ! -f /var/lib/gitea-runner-2/.runner ]; then
      cd /var/lib/gitea-runner-2
      TOKEN=$(cat /run/secrets/gitea-runner-token)
      ${pkgs.gitea-actions-runner}/bin/act_runner register --instance https://gitea.quadtech.dev --token "$TOKEN" --name backbone-runner-2 --no-interactive || true
    fi
  '';

  systemd.timers.git-pull = {
    description = "Pull git repo hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  systemd.services.git-pull = {
    script = "cd /etc/nixos && git pull";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };
  systemd.services.gitea-runner-3.preStart = ''
    mkdir -p /etc/gitea/runner /var/lib/gitea-runner-3
    cat > /etc/gitea/runner/config-3.yaml << EOF
runner:
  name: backbone-runner-3
  labels:
    - ubuntu-latest
    - linux
    - x86_64
    - self-hosted
  token: $(cat /run/secrets/gitea-runner-token)
  url: https://gitea.quadtech.dev
  state_dir: /var/lib/gitea-runner-3
EOF
    # Register runner if not already registered
    if [ ! -f /var/lib/gitea-runner-3/.runner ]; then
      cd /var/lib/gitea-runner-3
      TOKEN=$(cat /run/secrets/gitea-runner-token)
      ${pkgs.gitea-actions-runner}/bin/act_runner register --instance https://gitea.quadtech.dev --token "$TOKEN" --name backbone-runner-3 --no-interactive || true
    fi
  '';
}


