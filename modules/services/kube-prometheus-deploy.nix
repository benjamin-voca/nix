{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.quadnix.kube-prometheus-deploy;
  system = pkgs.stdenv.system;
  helmLib = import "${inputs.self}/lib/helm" {
    inherit (inputs) nixhelm nix-kube-generators;
    inherit pkgs system;
  };
  chart = helmLib.buildChart {
    name = "prometheus";
    chart = helmLib.charts.prometheus-community.kube-prometheus-stack;
    namespace = "monitoring";
    values = {
      prometheus = {
        prometheusSpec = {
          replicas = 2;
          retention = "30d";
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = [ "ReadWriteOnce" ];
                storageClassName = "longhorn";
                resources = {
                  requests = {
                    storage = "50Gi";
                  };
                };
              };
            };
          };
          resources = {
            requests = {
              cpu = "500m";
              memory = "2Gi";
            };
            limits = {
              cpu = "2000m";
              memory = "4Gi";
            };
          };
        };
      };

      grafana = {
        enabled = true;
        adminPassword = "changeme";
        ingress = {
          enabled = true;
          ingressClassName = "nginx";
          hosts = [ "grafana.k8s.quadtech.dev" ];
          tls = [{
            secretName = "grafana-tls";
            hosts = [ "grafana.k8s.quadtech.dev" ];
          }];
        };
        persistence = {
          enabled = true;
          size = "10Gi";
          storageClassName = "longhorn";
        };
      };

      alertmanager = {
        enabled = true;
        alertmanagerSpec = {
          replicas = 2;
          storage = {
            volumeClaimTemplate = {
              spec = {
                accessModes = [ "ReadWriteOnce" ];
                storageClassName = "longhorn";
                resources = {
                  requests = {
                    storage = "10Gi";
                  };
                };
              };
            };
          };
        };
      };

      nodeExporter = {
        enabled = true;
      };

      kubeStateMetrics = {
        enabled = true;
      };
    };
  };
in
{
  options.services.quadnix.kube-prometheus-deploy = {
    enable = lib.mkEnableOption "Deploy kube-prometheus-stack (Prometheus + Grafana) to Kubernetes";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "kube-prometheus-deploy";
        text = ''
          #!/bin/bash
          set -e
          export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

          kubectl="${pkgs.kubectl}/bin/kubectl"
          helm="${pkgs.kubernetes-helm}/bin/helm"

          echo "Waiting for Kubernetes API..."
          until $kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; do
            echo "Waiting for Kubernetes API..."
            sleep 5
          done

          echo "Waiting for ingress-nginx controller to be ready..."
          until $kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; do
            echo "Waiting for ingress-nginx controller..."
            sleep 5
          done

          echo "Waiting for Longhorn to be ready..."
          until $kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; do
            echo "Waiting for Longhorn..."
            sleep 5
          done

          echo "Creating monitoring namespace..."
          $kubectl create namespace monitoring --dry-run=client -o yaml | $kubectl apply -f - || true

          echo "Adding Prometheus Community helm repo..."
          $helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update 2>/dev/null || true
          $helm repo update

          if [ -f /run/secrets/grafana-admin-password ]; then
            GRAFANA_PASSWORD=$(cat /run/secrets/grafana-admin-password)
          else
            echo "Warning: grafana-admin-password secret not found, using default"
            GRAFANA_PASSWORD="admin"
          fi

          echo "Deploying kube-prometheus-stack..."
          $helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --version 0.80.2 \
            --set prometheus.enabled=true \
            --set prometheus.prometheusSpec.replicas=2 \
            --set prometheus.prometheusSpec.retention=30d \
            --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=longhorn \
            --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
            --set prometheus.prometheusSpec.resources.requests.cpu=500m \
            --set prometheus.prometheusSpec.resources.requests.memory=2Gi \
            --set prometheus.prometheusSpec.resources.limits.cpu=2000m \
            --set prometheus.prometheusSpec.resources.limits.memory=4Gi \
            --set alertmanager.enabled=true \
            --set alertmanager.alertmanagerSpec.replicas=2 \
            --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.storageClassName=longhorn \
            --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
            --set grafana.enabled=true \
            --set grafana.admin.password="$GRAFANA_PASSWORD" \
            --set grafana.ingress.enabled=true \
            --set grafana.ingress.ingressClassName=nginx \
            --set grafana.ingress.hosts[0]=grafana.k8s.quadtech.dev \
            --set grafana.ingress.tls[0].secretName=grafana-tls \
            --set grafana.ingress.tls[0].hosts[0]=grafana.k8s.quadtech.dev \
            --set grafana.persistence.enabled=true \
            --set grafana.persistence.storageClassName=longhorn \
            --set grafana.persistence.size=10Gi \
            --set nodeExporter.enabled=true \
            --set kubeStateMetrics.enabled=true \
            --wait --timeout 10m || true

          echo "Waiting for Prometheus to be ready..."
          for i in $(seq 1 60); do
            if $kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
              echo "Prometheus is ready"
              break
            fi
            echo "Waiting for Prometheus... ($i/60)"
            sleep 5
          done

          echo "Waiting for Grafana to be ready..."
          for i in $(seq 1 60); do
            if $kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
              echo "Grafana is ready"
              break
            fi
            echo "Waiting for Grafana... ($i/60)"
            sleep 5
          done

          echo "kube-prometheus-stack deployment complete!"
          echo "Grafana available at: https://grafana.k8s.quadtech.dev"
        '';
      })
      (pkgs.writeShellApplication {
        name = "kube-prometheus-cleanup";
        text = ''
          #!/bin/bash
          set -e
          export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig

          kubectl="${pkgs.kubectl}/bin/kubectl"
          helm="${pkgs.kubernetes-helm}/bin/helm"

          echo "Uninstalling kube-prometheus-stack..."
          $helm uninstall prometheus -n monitoring --ignore-not-found 2>/dev/null || true
          $kubectl delete ingress grafana -n monitoring --ignore-not-found 2>/dev/null || true
          $kubectl delete pvc -n monitoring -l app.kubernetes.io/name=prometheus --ignore-not-found 2>/dev/null || true
          $kubectl delete pvc -n monitoring -l app.kubernetes.io/name=grafana --ignore-not-found 2>/dev/null || true
          $kubectl delete pvc -n monitoring -l app.kubernetes.io/name=alertmanager --ignore-not-found 2>/dev/null || true
        '';
      })
      pkgs.kubectl
    ];

    systemd.services.kube-prometheus-deploy = {
      description = "Deploy kube-prometheus-stack to Kubernetes";
      after = [ "network-online.target" "kube-apiserver.service" ];
      wants = [ "network-online.target" "kube-apiserver.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/sw/bin/kube-prometheus-deploy";
        ExecStop = "/run/current-system/sw/bin/kube-prometheus-cleanup";
      };
    };
  };
}
