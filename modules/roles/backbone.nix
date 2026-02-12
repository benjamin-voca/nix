{ config, pkgs, ... }:

{
  imports = [
    ../profiles/base.nix
    ../profiles/server.nix
    ../profiles/docker.nix
    ../profiles/sops.nix
    ../profiles/kubernetes/control-plane.nix
    ../profiles/kubernetes/allow-master-workloads.nix
    ../profiles/kubernetes/helm.nix
    ../services/argocd-deploy.nix
    ../services/helm-charts.nix
    ../services/verdaccio-deploy.nix
    ../services/infiscal-deploy.nix
    ../gitea/runner.nix
  ];

  services.openiscsi = {
    enable = true;
    name = "iqn.2004-10.org.debian:${config.networking.hostName}";
  };

  systemd.tmpfiles.rules = [
    "L+ /usr/bin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
    "L+ /usr/sbin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
  ];

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

  # Additional packages
  environment.systemPackages = with pkgs; [
    apacheHttpd  # For htpasswd utility
    openssl
  ];

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
  - hostname: "*.quadtech.dev"
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


