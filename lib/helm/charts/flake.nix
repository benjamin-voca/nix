{
  description = "Nix-built Helm charts for QuadNix services";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    helm-charts.url = "github:argoproj/argo-helm/master";
  };

  outputs = { self, nixpkgs, flake-utils, helm-charts }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      
      # Helper to build Helm charts from source
      buildHelmChart = { chartName, chartVersion, src ? ./. }:
        pkgs.stdenv.mkDerivation {
          name = "${chartName}-${chartVersion}";
          inherit src;
          buildInputs = [ pkgs.kubernetes-helm ];
          buildPhase = ''
            # Copy chart files if they're not in the root
            if [ -d "charts/${chartName}" ]; then
              cp -r charts/${chartName}/* .
            fi
            
            # Validate chart structure
            helm lint .
            
            # Package the chart
            helm package . --version ${chartVersion} --app-version ${chartVersion} -d $out
          '';
          installPhase = "true";  # Output is the packaged .tgz in $out
        };
      
      # Build ArgoCD chart from upstream
      argocdChart = buildHelmChart {
        chartName = "argo-cd";
        chartVersion = "6.7.2";  # Update this when upgrading
        src = helm-charts.legacyPackages.${system}.argocd;
      };
      
      # Build Gitea chart (simplified version)
      giteaChart = buildHelmChart {
        chartName = "gitea";
        chartVersion = "4.4.0";  # Update this when upgrading
        src = pkgs.fetchFromGitHub {
          owner = "go-gitea";
          repo = "helm-charts";
          rev = "v${chartVersion}";
          hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Update this hash
        };
      };
      
      # Build Grafana chart
      grafanaChart = buildHelmChart {
        chartName = "grafana";
        chartVersion = "6.7.2";  # Update this when upgrading
        src = pkgs.fetchFromGitHub {
          owner = "grafana";
          repo = "helm-charts";
          rev = "v${chartVersion}";
          hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Update this hash
        };
      };
      
      # Build Loki chart
      lokiChart = buildHelmChart {
        chartName = "loki";
        chartVersion = "2.8.0";  # Update this when upgrading
        src = pkgs.fetchFromGitHub {
          owner = "grafana";
          repo = "helm-charts";
          rev = "v${chartVersion}";
          hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Update this hash
        };
      };
      
      # Build Tempo chart
      tempoChart = buildHelmChart {
        chartName = "tempo";
        chartVersion = "0.20.0";  # Update this when upgrading
        src = pkgs.fetchFromGitHub {
          owner = "grafana";
          repo = "helm-charts";
          rev = "v${chartVersion}";
          hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Update this hash
        };
      };
      
      # Build ClickHouse chart
      clickhouseChart = buildHelmChart {
        chartName = "clickhouse";
        chartVersion = "0.21.0";  # Update this when upgrading
        src = pkgs.fetchFromGitHub {
          owner = "clickhouse";
          repo = "clickhouse-operator";
          rev = "v${chartVersion}";
          hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Update this hash
        };
      };
      
      # Build Verdaccio chart
      verdaccioChart = buildHelmChart {
        chartName = "verdaccio";
        chartVersion = "4.29.0";  # Update this when upgrading
        src = pkgs.fetchFromGitHub {
          owner = "verdaccio";
          repo = "charts";
          rev = "v${chartVersion}";
          hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Update this hash
        };
      };
      
    in {
      packages.default = argocdChart;
      
      # Expose all charts
      packages.argocd = argocdChart;
      packages.gitea = giteaChart;
      packages.grafana = grafanaChart;
      packages.loki = lokiChart;
      packages.tempo = tempoChart;
      packages.clickhouse = clickhouseChart;
      packages.verdaccio = verdaccioChart;
      
      # Hydra jobs for CI
      hydraJobs = {
        argocd = argocdChart;
        gitea = giteaChart;
        grafana = grafanaChart;
        loki = lokiChart;
        tempo = tempoChart;
        clickhouse = clickhouseChart;
        verdaccio = verdaccioChart;
      };
    });
}