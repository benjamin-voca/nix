{config, ...}: {
  quad.hosts.frontline-01 = config.quad.lib.mkClusterHost {
    name = "frontline-01";
    system = "x86_64-linux";
    sshHost = "f1.quadtech.dev";
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
        sops.secrets.cloudflared-credentials = {
          sopsFile = ../../secrets/frontline-01.yaml;
          path = "/run/secrets/cloudflared-credentials.json";
          owner = "root";
          group = "root";
          mode = "0400";
        };

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

            for i in $(seq 1 30); do
              if [ -f /run/secrets/cloudflared-credentials.json ]; then
                break
              fi
              echo "Waiting for cloudflared credentials..."
              sleep 2
            done

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

            cp /run/secrets/cloudflared-credentials.json /etc/cloudflared/creds/credentials.json
            chmod 600 /etc/cloudflared/creds/credentials.json
          '';
        };
      })
    ];
  };
}
