{ config, lib, pkgs, ... }:

let
  cfg = config.services.cloudflared-k8s-deploy;
  tunnelCredentials = config.sops.secrets.cloudflared-credentials.path;
  kubectl = "${pkgs.kubectl}/bin/kubectl";

  manifests = pkgs.writeText "cloudflared-manifests.yaml" ''
    ---
    apiVersion: v1
    kind: Namespace
    metadata:
      name: cloudflared
      labels:
        app.kubernetes.io/name: cloudflared
        app.kubernetes.io/component: networking
        app.kubernetes.io/managed-by: quadnix
    ---
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: cloudflared-config
      namespace: cloudflared
    data:
      ingress.yaml: |
        tunnel: ${cfg.tunnelId}
        credentials-file: /etc/cloudflared/credentials.json

        ingress:
          - hostname: "*.quadtech.dev"
            service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
          - service: http_status:404
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: cloudflared
      namespace: cloudflared
      labels:
        app: cloudflared
    spec:
      replicas: ${toString cfg.replicas}
      selector:
        matchLabels:
          app: cloudflared
      template:
        metadata:
          labels:
            app: cloudflared
        spec:
          containers:
            - name: cloudflared
              image: cloudflare/cloudflared:${cfg.imageTag}
              args:
                - tunnel
                - --config
                - /etc/cloudflared/ingress.yaml
                - run
              env:
                - name: TUNNEL_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: cloudflared-tunnel-credentials
                      key: credentials.json
              ports:
                - containerPort: 2000
                  name: metrics
              livenessProbe:
                httpGet:
                  path: /ready
                  port: 2000
                initialDelaySeconds: 10
                periodSeconds: 10
                failureThreshold: 1
              resources:
                requests:
                  cpu: 50m
                  memory: 64Mi
                limits:
                  cpu: 200m
                  memory: 256Mi
              volumeMounts:
                - name: config
                  mountPath: /etc/cloudflared
                  readOnly: true
          volumes:
            - name: config
              configMap:
                name: cloudflared-config
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: cloudflared
      namespace: cloudflared
      labels:
        app: cloudflared
    spec:
      type: ClusterIP
      selector:
        app: cloudflared
      ports:
        - port: 2000
          targetPort: 2000
          name: metrics
  '';
in {
  options.services.cloudflared-k8s-deploy = {
    enable = lib.mkEnableOption "Deploy Cloudflare Tunnel to Kubernetes";

    tunnelId = lib.mkOption {
      type = lib.types.str;
      description = "Cloudflare Tunnel ID";
    };

    replicas = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Number of cloudflared replicas";
    };

    imageTag = lib.mkOption {
      type = lib.types.str;
      default = "2025.2.0";
      description = "Cloudflared image tag";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.kubectl ];

    systemd.services.cloudflared-k8s-deploy = {
      description = "Deploy Cloudflare Tunnel to Kubernetes";
      after = [ "network-online.target" "kube-apiserver.service" ];
      wants = [ "network-online.target" "kube-apiserver.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash";
        ExecStart += "-c";
        ExecStart += ''
          echo "Waiting for Kubernetes API..."
          until ${kubectl} cluster-info --request-timeout=10s >/dev/null 2>&1; do
            echo "Waiting for Kubernetes API..."
            sleep 5
          done
          echo "Kubernetes API is ready!"
          ${kubectl} apply -f ${manifests} --validate=false
          ${kubectl} create secret generic cloudflared-tunnel-credentials \
            --from-file=credentials.json=${tunnelCredentials} \
            --namespace=cloudflared \
            --dry-run=client -o yaml | ${kubectl} apply -f -
          echo "Cloudflare Tunnel deployed successfully!"
        '';
        ExecStop = "${pkgs.bash}/bin/bash";
        ExecStop += "-c";
        ExecStop += ''
          ${kubectl} delete secret cloudflared-tunnel-credentials -n cloudflared --ignore-not-found 2>/dev/null || true
          ${kubectl} delete -f ${manifests} --ignore-not-found 2>/dev/null || true
        '';
      };
    };
  };
}
