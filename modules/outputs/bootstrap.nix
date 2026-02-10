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
      
      # Import existing charts from lib/helm/charts
      existingCharts = import ../../lib/helm/charts { inherit helmLib; };
      
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

      # Cloudflared config with TCP ingress for SSH
      cloudflaredConfig = pkgs.writeText "config.yaml" (builtins.toJSON {
        tunnel = "b6bac523-be70-4625-8b67-fa78a9e1c7a5";
        credentials-file = "/etc/cloudflared/creds/credentials.json";
        metrics = "0.0.0.0:2000";
        no-autoupdate = true;
        ingress = [
          {
            hostname = "backbone-01.quadtech.dev";
            service = "ssh://localhost:22";
          }
          {
            hostname = "gitea.quadtech.dev";
            service = "http://gitea-http.gitea.svc.cluster.local:3000";
          }
          {
            hostname = "argocd.quadtech.dev";
            service = "http://argocd-server.argocd.svc.cluster.local:80";
          }
          {
            hostname = "*.quadtech.dev";
            service = "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80";
          }
          {
            service = "http_status:404";
          }
        ];
      });

      # Cloudflared deployment with config file
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
                command = [ "cloudflared" "tunnel" "--config" "/etc/cloudflared/config.yaml" "run" ];
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/etc/cloudflared/config";
                    readOnly = true;
                  }
                  {
                    name = "creds";
                    mountPath = "/etc/cloudflared/creds";
                    readOnly = true;
                  }
                ];
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
              volumes = [
                {
                  name = "config";
                  configMap = {
                    name = "cloudflared-config";
                    items = [
                      {
                        key = "config.yaml";
                        path = "config.yaml";
                      }
                    ];
                  };
                }
                {
                  name = "creds";
                  secret = {
                    secretName = "cloudflared-credentials";
                  };
                }
              ];
            };
          };
        };
      });

      # ConfigMap for cloudflared
      cloudflaredConfigMap = pkgs.writeText "cloudflared-configmap.yaml" (builtins.toJSON {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = "cloudflared-config";
          namespace = "cloudflared";
        };
        data = {
          "config.yaml" = builtins.readFile cloudflaredConfig;
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

      # Note: cloudflared credentials are mounted via Kubernetes secret
      # The secret 'cloudflared-credentials' should be created from sops-decrypted credentials

      # LoadBalancer service for direct SSH access (bypass Cloudflare Tunnel)
      giteaSSHLoadBalancer = pkgs.writeText "gitea-ssh-lb.yaml" (builtins.toJSON {
        apiVersion = "v1";
        kind = "Service";
        metadata = {
          name = "gitea-ssh-lb";
          namespace = "gitea";
          annotations = {
            "external-dns.alpha.kubernetes.io/hostname" = "gitea-ssh-direct.quadtech.dev";
          };
        };
        spec = {
          type = "LoadBalancer";
          ports = [{
            port = 2222;
            targetPort = 22;
            protocol = "TCP";
          }];
          selector = {
            "app.kubernetes.io/name" = "gitea";
            "app.kubernetes.io/instance" = "gitea";
          };
        };
      });

    in
      # Combine all charts and manifests into a single bootstrap output
      pkgs.runCommand "bootstrap-manifests" {} ''
        mkdir -p $out
        
        # Copy gitea chart from existing charts
        cp ${existingCharts.gitea} $out/01-gitea.yaml
        
        # Copy argocd chart
        cp ${argocdChart} $out/02-argocd.yaml
        
        # Write cloudflared namespace
        cp ${cloudflaredNamespace} $out/03-cloudflared-namespace.yaml
        
        # Write cloudflared configmap
        cp ${cloudflaredConfigMap} $out/04-cloudflared-configmap.yaml
        
        # Write cloudflared deployment
        cp ${cloudflaredManifest} $out/05-cloudflared-deployment.yaml

        # Write gitea SSH LoadBalancer
        cp ${giteaSSHLoadBalancer} $out/06-gitea-ssh-lb.yaml

        # Create combined file
        cat $out/01-gitea.yaml > $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/02-argocd.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/03-cloudflared-namespace.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/04-cloudflared-configmap.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/05-cloudflared-deployment.yaml >> $out/bootstrap.yaml
        echo "---" >> $out/bootstrap.yaml
        cat $out/06-gitea-ssh-lb.yaml >> $out/bootstrap.yaml
      '';

in
{
  config.flake.bootstrap = forAllSystems bootstrapFor;
}
