{ helmLib, pkgs, lib, ... }:

let
  # Generate secrets deterministically for this deployment
  redisSecret = pkgs.runCommand "argocd-redis-secret" {} ''
    mkdir -p $out
    echo -n "$(head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/base64)" > $out/redis-auth
  '';
in
{
  # ArgoCD configuration
  argocd = helmLib.buildChart {
    name = "argocd";
    chart = helmLib.charts.argoproj.argo-cd;
    namespace = "argocd";
    values = {
      global = {
        domain = "argocd.quadtech.dev";
      };

      configs = {
        cm = {
          "server.insecure" = true;
          url = "https://argocd.quadtech.dev";
        };
        params = {
          "server.insecure" = true;
        };
        # Create initial admin secret with server secret key
        secret = {
          argocdServerAdminPassword = lib.escapeShellArg "$2a$10$bX.6MmE5x1n.KlTA./3ax.xXzgP5CzLu1CyFyvMnEeh.vN9tDVVLC";
        };
        };
      };

      # Server configuration
      server = {
        replicas = 1;
        service = {
          type = "ClusterIP";
        };
        ingress = {
          enabled = true;
          ingressClassName = "nginx";
          hostname = "argocd.quadtech.dev";
          tls = false;
          annotations = {
            "nginx.ingress.kubernetes.io/proxy-body-size" = "0";
            "nginx.ingress.kubernetes.io/proxy-read-timeout" = "600";
            "nginx.ingress.kubernetes.io/proxy-send-timeout" = "600";
          };
          pathType = "Prefix";
          paths = [
            {
              path = "/";
              backend = {
                service = {
                  name = "argocd-server";
                  port = {
                    number = 80;
                  };
                };
              };
            }
          ];
        };
      };

      # Redis configuration
      redis = {
        enabled = true;
        password = lib.fileContents "${redisSecret}/redis-auth";
      };

      # Redis HA for high availability
      redis-ha = {
        enabled = false;
      };

      # Controller configuration
      controller = {
        replicas = 1;
      };

      # Repo server configuration - fix init container
      repoServer = {
        replicas = 1;
        volumes = [
          {
            name = "cmp-tmp";
            emptyDir = {};
          }
        ];
        volumeMounts = [
          {
            name = "cmp-tmp";
            mountPath = "/tmp";
          }
        ];
      };

      # ApplicationSet controller
      applicationSet = {
        enabled = true;
      };

      # Notifications controller
      notifications = {
        enabled = true;
      };

      # Global configuration
      global = {
        image = {
          tag = "v2.9.3";
        };
      };
    };
  };
}
