# Helm Chart Repositories Configuration
#
# This file tracks the Helm chart repositories and charts used in this project.
# To add new charts, you can either:
# 1. Contribute to nixhelm upstream (recommended for public charts)
# 2. Add them locally here for private/internal charts
#
# Repository format:
# {
#   name = "repo-name";
#   url = "https://charts.example.com" or "oci://registry.example.com/charts";
#   charts = [ "chart1" "chart2" ];
# }

{ }:

{
  # Define the chart repositories we want to track
  repositories = [
    {
      name = "argoproj";
      url = "https://argoproj.github.io/argo-helm";
      charts = [ "argo-cd" "argo-workflows" "argo-events" ];
    }
    {
      name = "prometheus-community";
      url = "https://prometheus-community.github.io/helm-charts";
      charts = [ "prometheus" "kube-prometheus-stack" "prometheus-operator" ];
    }
    {
      name = "bitnami";
      url = "https://charts.bitnami.com/bitnami";
      charts = [ "postgresql" "redis" "nginx" ];
    }
    {
      name = "jetstack";
      url = "https://charts.jetstack.io";
      charts = [ "cert-manager" ];
    }
    {
      name = "ingress-nginx";
      url = "https://kubernetes.github.io/ingress-nginx";
      charts = [ "ingress-nginx" ];
    }
    {
      name = "metallb";
      url = "https://metallb.github.io/metallb";
      charts = [ "metallb" ];
    }
    {
      name = "gitea-charts";
      url = "https://dl.gitea.com/charts";
      charts = [ "gitea" ];
    }
    {
      name = "clickhouse";
      url = "https://docs.altinity.com/clickhouse-operator";
      charts = [ "clickhouse-operator" "clickhouse" ];
    }
    {
      name = "grafana";
      url = "https://grafana.github.io/helm-charts";
      charts = [ "grafana" "loki" "tempo" "mimir" ];
    }
  ];

  # OCI repositories (using oci:// scheme)
  ociRepositories = [
    # Example OCI repository
    # {
    #   name = "ghcr-myorg";
    #   url = "oci://ghcr.io/myorg/charts";
    #   charts = [ "mychart" ];
    # }
  ];
}
