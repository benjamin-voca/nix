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
        
        # Copy gitea chart from existing charts
        cp ${existingCharts.gitea} $out/01-gitea.yaml
        
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
