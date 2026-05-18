# Cloudflared bootstrap module
# Cloudflared namespace + configmap + deployment
{
  pkgs,
  lib,
}: let
  # Cloudflared config content as string
  cloudflaredConfigContent = builtins.toJSON (import ../../../lib/cloudflared-config.nix {
    tunnelId = "b6bac523-be70-4625-8b67-fa78a9e1c7a5";
    credentialsFile = "/etc/cloudflared/creds/credentials.json";
    metrics = "0.0.0.0:2002";
  });

  cloudflaredNamespace = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: cloudflared
      labels:
        app.kubernetes.io/name: cloudflared
  '';

  cloudflaredDeployment = ''
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: cloudflared
      namespace: cloudflared
      labels:
        app: cloudflared
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: cloudflared
      template:
        metadata:
          labels:
            app: cloudflared
        spec:
          hostNetwork: true
          containers:
          - name: cloudflared
            image: cloudflare/cloudflared:latest
            command: ["cloudflared", "tunnel", "--config", "/etc/cloudflared/config/config.yaml", "run"]
            volumeMounts:
            - name: config
              mountPath: /etc/cloudflared/config
              readOnly: true
            - name: creds
              mountPath: /etc/cloudflared/creds
              readOnly: true
            resources:
              requests:
                cpu: 100m
                memory: 128Mi
              limits:
                cpu: 500m
                memory: 256Mi
          volumes:
          - name: config
            configMap:
              name: cloudflared-config
              items:
              - key: config.yaml
                path: config.yaml
          - name: creds
            secret:
              secretName: cloudflared-credentials

  '';
in {
  chartFiles = {};

  inlineFiles = {
    "05-cloudflared-namespace.yaml" = cloudflaredNamespace;
    "06-cloudflared-deployment.yaml" = cloudflaredDeployment;
  };

  # Cloudflared configmap needs special handling (JSON content indented into YAML)
  cloudflaredConfigContent = cloudflaredConfigContent;

  order = ["05-cloudflared-namespace.yaml" "05-cloudflared-configmap.yaml" "06-cloudflared-deployment.yaml"];
}
