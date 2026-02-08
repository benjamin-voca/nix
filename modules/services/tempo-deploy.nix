{ config, lib, pkgs, ... }:

{
  options.services.quadnix.tempo-deploy = {
    enable = lib.mkEnableOption "Deploy Tempo for distributed tracing with HA";
    
    replicas = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Number of Tempo replicas for HA";
    };
    
    storage = {
      type = lib.mkOption {
        type = lib.types.enum [ "local" "s3" "gcs" "azure" ];
        default = "local";
        description = "Storage backend for Tempo";
      };
      
      size = lib.mkOption {
        type = lib.types.str;
        default = "50Gi";
        description = "Storage size for Tempo";
      };
    };
  };

  config = lib.mkIf config.services.quadnix.tempo-deploy.enable {
    # Tempo chart configuration
    environment.etc."tempo/values.yaml".text = lib.generators.toYAML {} {
      # Tempo configuration
      tempo = {
        replicas = 1;
        
        storage = {
          trace = {
            backend = config.services.quadnix.tempo-deploy.storage.type;
            local = {
              path = "/var/tempo/traces";
            };
            s3 = {
              bucket = "tempo-traces";
              endpoint = "s3.amazonaws.com";
              region = "us-east-1";
              access_key_id = "${config.sops.secrets.tempo-s3-access-key.path}";
              secret_access_key = "${config.sops.secrets.tempo-s3-secret-key.path}";
            };
          };
        };

        receivers = {
          jaeger = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:14250";
              };
              thrift_http = {
                endpoint = "0.0.0.0:14268";
              };
            };
          };
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317";
              };
              http = {
                endpoint = "0.0.0.0:4318";
              };
            };
          };
        };
      };

      # Persistence
      persistence = {
        enabled = true;
        size = config.services.quadnix.tempo-deploy.storage.size;
      };

      # Service monitor
      serviceMonitor = {
        enabled = true;
      };
      
      # Node affinity for backbone placement
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [{
              matchExpressions = [{
                key = "role";
                operator = "In";
                values = [ "backbone" ];
              }];
            }];
          };
        };
      };
      
      # Tolerations for backbone taints
      tolerations = [
        { key = "role"; operator = "Equal"; value = "backbone"; effect = "NoSchedule"; }
        { key = "infra"; operator = "Equal"; value = "true"; effect = "NoSchedule"; }
      ];
    };

    # Tempo ServiceMonitor for Prometheus
    environment.etc."tempo/servicemonitor.yaml".text = lib.generators.toYAML {} {
      apiVersion: monitoring.coreos.com/v1
      kind: ServiceMonitor
      metadata:
        name: tempo
        namespace: tempo
        labels:
          app: tempo
      spec:
        selector:
          matchLabels:
            app: tempo
        endpoints:
        - port: http-metrics
          path: /metrics
          interval: 30s
          scrapeTimeout: 10s
    };
  };
}