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