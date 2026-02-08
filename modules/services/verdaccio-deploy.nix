{ config, lib, pkgs, ... }:

let
  cfg = config.services.quadnix.verdaccio-deploy;
  kubectl = "${pkgs.kubectl}/bin/kubectl";
  
  deployScript = pkgs.writeShellApplication {
    name = "verdaccio-deploy";
    text = ''
      #!/bin/bash
      set -e
      sleep 120
      export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig
      
      echo "Waiting for Kubernetes API..."
      until ${kubectl} cluster-info --request-timeout=10s >/dev/null 2>&1; do
        echo "Waiting for Kubernetes API..."
        sleep 5
      done
      
      echo "Creating Verdaccio prerequisites..."
      
      # Create namespace
      ${kubectl} create namespace verdaccio --dry-run=client -o yaml | ${kubectl} apply -f - || true
      
      # Create config file
       CONFIG_FILE=$(mktemp)
       cat > "$CONFIG_FILE" << 'CONFIGEOF'
      storage: /verdaccio/storage

      auth:
        htpasswd:
          file: /verdaccio/conf/htpasswd
          max_users: 1000

      uplinks:
        npmjs:
          url: https://registry.npmjs.org/

      packages:
        "@quadcoretech/*":
          access: $authenticated
          publish: $authenticated
          proxy: npmjs

        "**":
          access: $all
          publish: $authenticated
          proxy: npmjs

      web:
        enable: true
        title: QuadTech NPM Registry
        logo: https://verdaccio.org/img/logo/symbol/svg/verdaccio-tiny.svg

      middlewares:
        audit:
          enabled: true

      log:
        type: stdout
        format: pretty
        level: http

      listen: 0.0.0.0:4873
      CONFIGEOF
      
       ${kubectl} create secret generic verdaccio-config \
         --from-file=config.yaml="$CONFIG_FILE" \
        --namespace=verdaccio \
        --dry-run=client -o yaml | ${kubectl} apply -f -
      
       rm "$CONFIG_FILE"
       
       # Create htpasswd file with admin user
       # Generate Apache md5 hash for admin:adminpass123
       ADMIN_HASH=$(${pkgs.apacheHttpd}/bin/htpasswd -nbB admin adminpass123 2>/dev/null | cut -d: -f2)
       
       HTPASSWD_FILE=$(mktemp)
       echo "admin:$ADMIN_HASH" > "$HTPASSWD_FILE"
       
       ${kubectl} create secret generic verdaccio-htpasswd \
         --from-file=htpasswd="$HTPASSWD_FILE" \
         --namespace=verdaccio \
         --dry-run=client -o yaml | ${kubectl} apply -f -
       
       rm "$HTPASSWD_FILE"
      
      echo "Deploying Verdaccio..."
      
      # Add verdaccio helm repo
      ${pkgs.kubernetes-helm}/bin/helm repo add verdaccio https://charts.verdaccio.org --force-update 2>/dev/null || true
      ${pkgs.kubernetes-helm}/bin/helm repo update
      
      # Deploy using helm
      ${pkgs.kubernetes-helm}/bin/helm upgrade --install verdaccio verdaccio/verdaccio \
        --namespace verdaccio \
        --version 4.29.0 \
        --set service.type=ClusterIP \
        --set ingress.enabled=true \
        --set ingress.className=nginx \
        --set ingress.hosts[0]=verdaccio.quadtech.dev \
        --set persistence.enabled=false \
        --set volumes[0].name=config \
        --set volumes[0].secret.secretName=verdaccio-config \
        --set volumeMounts[0].name=config \
        --set volumeMounts[0].mountPath=/verdaccio/conf \
        --set volumes[1].name=htpasswd \
        --set volumes[1].secret.secretName=verdaccio-htpasswd \
        --set volumeMounts[1].name=htpasswd \
        --set volumeMounts[1].mountPath=/verdaccio/conf \
        --set volumeMounts[1].subPath=htpasswd \
        --set securityContext.fsGroup=10001 \
        --set securityContext.runAsUser=10001 \
        --set securityContext.runAsGroup=10001 \
        --wait --timeout 5m || true
      
      echo "Verdaccio deployed successfully!"
      echo "Admin username: admin"
      echo "Admin password: adminpass123"
    '';
  };

  cleanupScript = pkgs.writeShellApplication {
    name = "verdaccio-cleanup";
    text = ''
      #!/bin/bash
      set -e
      export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig
      ${pkgs.kubernetes-helm}/bin/helm uninstall verdaccio -n verdaccio --ignore-not-found 2>/dev/null || true
    '';
  };
in
{
  options.services.quadnix.verdaccio-deploy = {
    enable = lib.mkEnableOption "Deploy Verdaccio npm registry to Kubernetes";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      deployScript
      cleanupScript
      pkgs.kubectl
      pkgs.kubernetes-helm
    ];

    systemd.services.verdaccio-deploy = {
      description = "Deploy Verdaccio npm registry to Kubernetes";
      after = [ "network-online.target" "kube-apiserver.service" ];
      wants = [ "network-online.target" "kube-apiserver.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${deployScript}/bin/verdaccio-deploy";
        ExecStop = "${cleanupScript}/bin/verdaccio-cleanup";
      };
    };
  };
}
