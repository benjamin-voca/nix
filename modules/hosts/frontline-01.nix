{config, ...}: {
  quad.hosts.frontline-01 = config.quad.lib.mkClusterHost {
    name = "frontline-01";
    system = "x86_64-linux";
    sshHost = "frontline01";
    remoteBuild = true;
    hardwareModule = ../hardware/frontline-01.nix;
    roleModule = ../roles/frontline.nix;
    taints = [
      {
        key = "role";
        value = "frontline";
        effect = "NoSchedule";
      }
    ];
    extraModules = [
      ({pkgs, ...}: {
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
}
