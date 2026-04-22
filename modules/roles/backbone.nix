{
  config,
  pkgs,
  ...
}: {
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
    ../services/argocd-apps.nix
    ../services/k8s-secrets-inject.nix
    ../services/forgejo-migration-cleanup.nix
  ];

  environment.systemPackages = with pkgs; [
    git
    nfs-utils
    openiscsi
    apacheHttpd # For htpasswd utility
    openssl
    procps # For pkill command used by cloudflared scripts
  ];

  services.openiscsi = {
    enable = true;
    name = "iqn.2026-04.dev.quadtech:${config.networking.hostName}";
  };

  networking.firewall.allowedTCPPorts = [
    22
    443
    6443
  ];

  networking.hosts."192.168.1.240" = [
    "harbor.quadtech.dev"
  ];

  sops.secrets = {
    cloudflared-credentials = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/cloudflared-credentials.json";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    forgejo-db-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
    };
    argocd-admin-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/argocd-admin-password";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    forgejo-runner-token = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/forgejo-runner-token";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    forgejo-admin-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/forgejo-admin-password";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    argocd-forgejo-username = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/argocd-forgejo-username";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    argocd-forgejo-token = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/argocd-forgejo-token";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    harbor-admin-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/harbor-admin-password";
    };
    harbor-registry-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/harbor-registry-password";
    };
    cnpg-edukurs-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/cnpg-edukurs-password";
    };
    ceph-rgw-s3-access-key = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/ceph-rgw-s3-access-key";
    };
    ceph-rgw-s3-secret-key = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/ceph-rgw-s3-secret-key";
    };
    minecraft-rcon-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/minecraft-rcon-password";
    };
    verdaccio-admin-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/verdaccio-admin-password";
    };
    erpnext-db-admin-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/erpnext-db-admin-password";
    };
    erpnext-admin-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/erpnext-admin-password";
    };
    openclaw-gateway-token = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/openclaw-gateway-token";
    };
    openclaw-minimax-api-key = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/openclaw-minimax-api-key";
    };
    openclaw-discord-id = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/openclaw-discord-id";
    };
    forgejo-agent-token = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/forgejo-agent-token";
    };
    orkestr-db-password = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/orkestr-db-password";
    };
    orkestr-secret-key-base = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/orkestr-secret-key-base";
    };
    orkestr-token-signing-secret = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/orkestr-token-signing-secret";
    };
    orkestr-electric-secret = {
      sopsFile = ../../secrets/${config.networking.hostName}.yaml;
      path = "/run/secrets/orkestr-electric-secret";
    };
  };

  services.quadnix.argocd-deploy = {
    enable = true;
  };

  services.quadnix.verdaccio-deploy = {
    enable = false;
  };

  services.quadnix.argocdApps = {
    enable = true;
    harbor = true;
    verdaccio = false;
  };

  services.quadnix.k8s-secrets-inject = {
    enable = true;
  };

  services.quadnix.forgejo-migration-cleanup = {
    enable = true;
  };

  # Forgejo Actions runners are managed in Kubernetes via forgejo-actions chart.

  # Cloudflared tunnel service (runs on host for SSH access via Cloudflare Tunnel)
  # Uses host IP 192.168.1.15 with NodePorts for K8s services
  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    wantedBy = ["multi-user.target"];
    wants = ["network.target"];
    after = ["network.target"];
    enable = true;
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --protocol http2 --config /etc/cloudflared/config/config.yaml run";
      Restart = "always";
      RestartSec = "5s";
      User = "root";
    };
    unitConfig = {
      StartLimitIntervalSec = "0";
    };
  };

  # Create cloudflared config directory and files
  systemd.services.cloudflared.preStart = ''
        mkdir -p /etc/cloudflared/config /etc/cloudflared/creds

        # Wait for the secret to be available
        for i in $(seq 1 30); do
          if [ -f /run/secrets/cloudflared-credentials.json ]; then
            break
          fi
          echo "Waiting for cloudflared credentials..."
          sleep 2
        done

        # Write cloudflared config - use 127.0.0.1 with NodePorts
        cat > /etc/cloudflared/config/config.yaml << 'EOF'
    tunnel: b6bac523-be70-4625-8b67-fa78a9e1c7a5
    credentials-file: /etc/cloudflared/creds/credentials.json
    protocol: http2
    metrics: 0.0.0.0:2003
    no-autoupdate: true
    ingress:
      - hostname: backbone-01.quadtech.dev
        service: ssh://127.0.0.1:22
      - hostname: forge-ssh.quadtech.dev
        service: tcp://127.0.0.1:32222
      - hostname: forge.quadtech.dev
        service: http://127.0.0.1:30856
      - hostname: argocd.quadtech.dev
        service: http://127.0.0.1:30856
      - hostname: harbor.quadtech.dev
        service: http://127.0.0.1:30856
      - hostname: educourses-pd.com
        service: http://127.0.0.1:30856
      - hostname: www.educourses-pd.com
        service: http://127.0.0.1:30856
      - hostname: openclaw.quadtech.dev
        service: http://127.0.0.1:30856
      - hostname: grafana.k8s.quadtech.dev
        service: http://127.0.0.1:30856
      - hostname: app.orkestr-os.com
        service: http://127.0.0.1:30856
      - hostname: api.orkestr-os.com
        service: http://127.0.0.1:30856
      - service: http_status:404
    EOF

        # Copy credentials from SOPS secret
        cp /run/secrets/cloudflared-credentials.json /etc/cloudflared/creds/credentials.json
        chmod 600 /etc/cloudflared/creds/credentials.json
  '';

  # Host-based runners removed - runners now run on Kubernetes via forgejo-actions helm chart

  systemd.timers.git-pull = {
    description = "Pull git repo hourly";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  systemd.services.git-pull = {
    script = "cd /etc/nixos && ${pkgs.git}/bin/git pull";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };
}
