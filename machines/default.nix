# machines/default.nix — Machine Registry
#
# This is the source of truth for all machines in the cluster.
# Machines reference roles by name; roles are NixOS modules.
#
# Secrets layering: shared.yaml → role.yaml → host.yaml (later wins)
# Secret files are listed per-machine; requiredSecrets per-role.
# Typed secrets infrastructure is ready but NOT wired into consumer yet.
# Actual secrets remain in secrets/backbone-01.yaml and secrets/frontline-01.yaml.
{
  machines = {
    backbone-01 = {
      system = "x86_64-linux";
      hardware = ../modules/hardware/backbone-01.nix;
      role = "backbone";
      sshHost = "backbone01";
      remoteBuild = true;
      taints = [
        { key = "role"; value = "backbone"; effect = "NoSchedule"; }
        { key = "infra"; value = "true"; effect = "NoSchedule"; }
      ];
      secrets = {
        files = [
          ../secrets/shared.yaml
          ../secrets/roles/backbone.yaml
          ../secrets/hosts/backbone-01.yaml
        ];
      };
      extraModules = [
        ({ lib, ... }: {
          boot.loader.grub.enable = lib.mkForce false;
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;
          boot.loader.efi.efiSysMountPoint = "/boot";
        })
      ];
    };

    frontline-01 = {
      system = "x86_64-linux";
      hardware = ../modules/hardware/frontline-01.nix;
      role = "worker";
      sshHost = "frontline01";
      remoteBuild = true;
      taints = [
        { key = "role"; value = "frontline"; effect = "NoSchedule"; }
      ];
      secrets = {
        files = [
          ../secrets/shared.yaml
          ../secrets/roles/worker.yaml
          ../secrets/hosts/frontline-01.yaml
        ];
      };
      extraModules = [
        ({ pkgs, ... }: {
          # cloudflared tunnel for SSH (machine-specific)
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
            preStart = ''
              mkdir -p /etc/cloudflared/config /etc/cloudflared/creds

              cat > /etc/cloudflared/config/config.yaml << 'EOF'
              ${builtins.toJSON {
                tunnel = "d7584f63-ae28-4b8d-b3ea-f4a491d1e01e";
                "credentials-file" = "/etc/cloudflared/creds/credentials.json";
                protocol = "http2";
                metrics = "0.0.0.0:2003";
                "no-autoupdate" = true;
                ingress = [
                  {
                    hostname = "f1.quadtech.dev";
                    service = "ssh://localhost:22";
                  }
                  {
                    service = "http_status:404";
                  }
                ];
              }}
              EOF

              cat > /etc/cloudflared/creds/credentials.json << 'EOF'
              ${builtins.toJSON {
                AccountTag = "e8ce039ed83299a01dad579f1866b6e2";
                TunnelSecret = "FONry/HvjV5cQ7RBBOsD/tL4JfJQc8zby3OM4r//FSE=";
                TunnelID = "d7584f63-ae28-4b8d-b3ea-f4a491d1e01e";
              }}
              EOF
              chmod 600 /etc/cloudflared/creds/credentials.json
            '';
          };
        })
      ];
    };
  };

  roles = {
    backbone = {
      module = ../modules/roles/backbone.nix;
      description = "Kubernetes control-plane + ArgoCD + Forgejo + Harbor";
      requiredSecrets = [
        # Cloudflared tunnel
        "cloudflared-credentials"
        # Forgejo
        "forgejo-db-password"
        "forgejo-admin-password"
        "forgejo-runner-token"
        "forgejo-agent-token"
        # ArgoCD
        "argocd-admin-password"
        "argocd-forgejo-username"
        "argocd-forgejo-token"
        # Harbor
        "harbor-admin-password"
        "harbor-registry-password"
        # Ceph S3
        "ceph-rgw-s3-access-key"
        "ceph-rgw-s3-secret-key"
        # Minecraft
        "minecraft-rcon-password"
        # Verdaccio
        "verdaccio-admin-password"
        # ERPNext
        "erpnext-db-admin-password"
        "erpnext-admin-password"
        # OpenClaw
        "openclaw-gateway-token"
        "openclaw-minimax-api-key"
        "openclaw-discord-id"
        # Orkestr
        "orkestr-db-password"
        "orkestr-secret-key-base"
        "orkestr-token-signing-secret"
        "orkestr-electric-secret"
        # LibreChat
        "librechat-zhipu-api-key"
        "librechat-minimax-api-key"
        "librechat-jwt-secret"
        # Tailscale
        "tailscale-auth-key"
      ];
    };

    worker = {
      module = ../modules/roles/worker.nix;
      description = "Kubernetes worker node";
      requiredSecrets = [
        "cloudflared-credentials"
      ];
    };
  };
}
