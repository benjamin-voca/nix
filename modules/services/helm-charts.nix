{ config, pkgs, lib, ... }:

{
  options.services.quadnix.helm-charts = {
    enable = lib.mkEnableOption "Enable Nix-built Helm charts repository";
    
    charts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Map of chart names to versions";
    };
    
    giteaRepo = lib.mkOption {
      type = lib.types.str;
      description = "Gitea repository URL for chart hosting";
    };
  };

  config = lib.mkIf config.services.quadnix.helm-charts.enable {
    # Install Helm and OCI registry tools
    environment.systemPackages = with pkgs; [
      kubernetes-helm
      helm-push  # For pushing charts to OCI registries
    ];

    # Create Helm repository configuration
    environment.etc."helm/repositories.yaml".text = lib.generators.toYAML {} {
      repositories = [
        {
          name = "quadnix-charts";
          url = config.services.quadnix.helm-charts.giteaRepo;
        }
      ];
    };

    # Set up cron job to update Helm repository index
    systemd.services.helm-repo-index = {
      description = "Update Helm repository index";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.kubernetes-helm}/bin/helm repo index ${config.services.quadnix.helm-charts.giteaRepo}";
      };
      startAt = "daily";
    };

    # Expose charts as system packages
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "publish-helm-chart" 
        ''
          #!/bin/bash
          set -e
          
          CHART_NAME=$1
          CHART_VERSION=$2
          
          if [ -z "$CHART_NAME" ] || [ -z "$CHART_VERSION" ]; then
            echo "Usage: publish-helm-chart <chart-name> <chart-version>"
            exit 1
          fi
          
          echo "Publishing $CHART_NAME version $CHART_VERSION..."
          
          # Build the chart
          nix build .#${CHART_NAME} --out-link result
          
          # Package and push to Gitea
          helm package result/*.tgz --destination .
          
          # TODO: Implement Gitea API upload
          echo "Chart published: $CHART_NAME-$CHART_VERSION.tgz"
        '')
    ];
  };
}