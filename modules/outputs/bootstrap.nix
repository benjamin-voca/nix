{ config, lib, inputs, ... }:

let
  systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  forAllSystems = lib.genAttrs systems;

  # Helper to get pkgs for a system
  pkgsFor = system: inputs.nixpkgs.legacyPackages.${system};

  # Helper to get helmLib for a system  
  helmLibFor = system:
    let
      pkgs = pkgsFor system;
    in
      import ../../lib/helm {
        inherit (inputs) nixhelm nix-kube-generators;
        inherit pkgs system;
      };

  # Get charts from nixhelm
  chartsFor = system: inputs.nixhelm.chartsDerivations.${system};

  # Bootstrap output that merges gitea, argocd, and cloudflare
  bootstrapFor = system:
    let
      pkgs = pkgsFor system;
      charts = chartsFor system;
      helmLib = helmLibFor system;
      kubelib = inputs.nix-kube-generators.lib { inherit pkgs; };
      
      # Gitea chart configuration
      giteaChart = pkgs.lib.pipe
        {
          name = "gitea";
          chart = helmLib.kubelib.downloadHelmChart {
            repo = "https://dl.gitea.com/charts";
            chart = "gitea";
            version = "12.5.0";
            chartHash = "sha256-6sG9xCpbbRMMDlsZtHzqrNWuqsT/NHalUVUv0Ltx/zA=";
          };
          namespace = "gitea";
          values = {
            image = {
              repository = "gitea/gitea";
              tag = "1.25.4";
            };
            replicaCount = 1;
            service = {
              http = {
                type = "ClusterIP";
                port = 3000;
              };
              ssh = {
                create = true;
                type = "ClusterIP";
                port = 22;
                annotations = {
                  "external-dns.alpha.kubernetes.io/hostname" = "gitea-ssh-internal.quadtech.dev";
                };
              };
            };
            ingress = {
              enabled = true;
              className = "nginx";
              annotations = {
                "nginx.ingress.kubernetes.io/proxy-body-size" = "512m";
              };
              hosts = [{
                host = "gitea.quadtech.dev";
                paths = [{
                  path = "/";
                  pathType = "Prefix";
                }];
              }];
              tls = [];
            };
            persistence = {
              enabled = true;
              create = true;
              mount = true;
              size = "50Gi";
              storageClass = "longhorn";
              claimName = "gitea-shared-storage";
            };
            postgresql.enabled = false;
            postgresql-ha.enabled = false;
            redis-cluster.enabled = false;
            valkey-cluster.enabled = false;
            gitea = {
              admin = {
                existingSecret = "gitea-admin";
                username = "gitea_admin";
                password = "REPLACE_ME";
                email = "admin@quadtech.dev";
              };
              config = {
                log = {
                  MODE = "console";
                  ROOT_PATH = "/data/gitea/custom/log";
                };
                server = {
                  DOMAIN = "gitea.quadtech.dev";
                  ROOT_URL = "https://gitea.quadtech.dev";
                  SSH_DOMAIN = "gitea.quadtech.dev";
                  SSH_PORT = 2222;
                  DISABLE_SSH = false;
                  START_SSH_SERVER = true;
                  SSH_LISTEN_PORT = 22;
                };
                ssh.create = true;
                database = {
                  DB_TYPE = "postgres";
                  HOST = "gitea-db-rw.gitea.svc.cluster.local:5432";
                  NAME = "gitea";
                  USER = "gitea";
                  PASSWD = "REPLACE_ME";
                  SSL_MODE = "disable";
                };
                cache = {
                  ENABLED = true;
                  ADAPTER = "memory";
                };
                session.PROVIDER = "memory";
                queue.TYPE = "level";
                service = {
                  DISABLE_REGISTRATION = true;
                  REQUIRE_SIGNIN_VIEW = true;
                  ENABLE_NOTIFY_MAIL = false;
                };
                actions.ENABLED = true;
                repository = {
                  DEFAULT_BRANCH = "main";
                  ENABLE_PUSH_CREATE_USER = true;
                  ENABLE_PUSH_CREATE_ORG = true;
                };
                webhook.ALLOWED_HOST_LIST = "*";
              };
              additionalConfigFromEnvs = [
                {
                  name = "GITEA__DATABASE__PASSWD";
                  valueFrom = {
                    secretKeyRef = {
                      name = "gitea-db";
                      key = "password";
                    };
                  };
                }
              ];
            };
            resources = {
              requests = {
                cpu = "200m";
                memory = "512Mi";
              };
              limits = {
                cpu = "2000m";
                memory = "2Gi";
              };
            };
            initContainers = {
              initDirectories.enabled = false;
              initAppIni.enabled = false;
              configureGitea.enabled = false;
            };
            affinity = {};
          };
        }
        [
          kubelib.buildHelmChart
        ];

      # ArgoCD chart configuration  
      argocdChart = pkgs.lib.pipe
        {
          name = "argocd";
          chart = charts.argoproj.argo-cd;
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
              secret = {
                argocdServerAdminPassword = "$2a$10$bX.6MmE5x1n.KlTA./3ax.xXzgP5CzLu1CyFyvMnEeh.vN9tDVVLC";
              };
            };
            server = {
              replicas = 1;
              service = {
                type = "ClusterIP";
              };
            };
            redis.enabled = true;
            redis-ha.enabled = false;
            controller.replicas = 1;
            repoServer.replicas = 1;
            applicationSet.enabled = true;
            notifications.enabled = true;
            global.image.tag = "v2.9.3";
          };
        }
        [
          kubelib.buildHelmChart
        ];

      # Cloudflared - using a Kubernetes deployment manifest since there's no official Helm chart in nixhelm
      cloudflaredManifest = pkgs.writeText "cloudflared.yaml" (builtins.toJSON {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = "cloudflared";
          namespace = "cloudflared";
          labels = {
            app = "cloudflared";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "cloudflared";
          template = {
            metadata.labels.app = "cloudflared";
            spec = {
              hostNetwork = true;
              containers = [{
                name = "cloudflared";
                image = "cloudflare/cloudflared:latest";
                command = [ "cloudflared" "tunnel" "run" "--token" "$(TUNNEL_TOKEN)" ];
                env = [{
                  name = "TUNNEL_TOKEN";
                  valueFrom = {
                    secretKeyRef = {
                      name = "cloudflared-credentials";
                      key = "token";
                    };
                  };
                }];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "256Mi";
                  };
                };
              }];
            };
          };
        };
      });

      # Create namespace for cloudflared
      cloudflaredNamespace = pkgs.writeText "cloudflared-namespace.yaml" (builtins.toJSON {
        apiVersion = "v1";
        kind = "Namespace";
        metadata = {
          name = "cloudflared";
          labels = {
            "app.kubernetes.io/name" = "cloudflared";
          };
        };
      });

    in
      # Combine all charts and manifests into a single bootstrap output
      pkgs.runCommand "bootstrap-manifests" {} ''
        mkdir -p $out
        
        # Copy gitea chart
        cp ${giteaChart} $out/01-gitea.yaml
        
        # Copy argocd chart
        cp ${argocdChart} $out/02-argocd.yaml
        
        # Write cloudflared namespace
        cp ${cloudflaredNamespace} $out/03-cloudflared-namespace.yaml
        
        # Write cloudflared deployment
        cp ${cloudflaredManifest} $out/04-cloudflared-deployment.yaml
        
        # Create combined file
        cat $out/01-gitea.yaml > $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02-argocd.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/03-cloudflared-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/04-cloudflared-deployment.yaml >> $out/bootstrap.yaml
      '';

in
{
  config.flake.bootstrap = forAllSystems bootstrapFor;
}
