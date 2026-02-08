{ config, lib, pkgs, ... }:

{
  options.services.quadnix.loki-deploy = {
    enable = lib.mkEnableOption "Deploy Loki for log aggregation with HA";
    
    replicas = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Number of Loki replicas for HA";
    };
    
    storage = {
      type = lib.mkOption {
        type = lib.types.enum [ "filesystem" "s3" "gcs" "azure" ];
        default = "filesystem";
        description = "Storage backend for Loki";
      };
      
      size = lib.mkOption {
        type = lib.types.str;
        default = "100Gi";
        description = "Storage size for Loki";
      };
    };
  };

  config = lib.mkIf config.services.quadnix.loki-deploy.enable {
    # Loki chart configuration
    environment.etc."loki/values.yaml".text = lib.generators.toYAML {} {
      # Loki configuration
      loki = {
        auth_enabled = false;
        
        commonConfig = {
          replication_factor = 1;
        };

        storage = {
          type = config.services.quadnix.loki-deploy.storage.type;
          filesystem = {
            volume_claim_template = {
              spec = {
                accessModes = [ "ReadWriteOnce" ];
                resources = {
                  requests = {
                    storage = config.services.quadnix.loki-deploy.storage.size;
                  };
                };
                storageClassName = "local-path";
              };
            };
          };
          
          s3 = {
            bucketnames = "loki";
            endpoint = "s3.amazonaws.com";
            region = "us-east-1";
            access_key_id = "${config.sops.secrets.loki-s3-access-key.path}";
            secret_access_key = "${config.sops.secrets.loki-s3-secret-key.path}";
          };
        };

        schemaConfig = {
          configs = [{
            from = "2024-01-01";
            store = "tsdb";
            object_store = config.services.quadnix.loki-deploy.storage.type;
            schema = "v12";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }];
        };
      };

      # Deployment mode
      deploymentMode = "SimpleScalable";

      # Backend (read/write components)
      backend = {
        replicas = 1;
        persistence = {
          enabled = true;
          size = config.services.quadnix.loki-deploy.storage.size;
        };
      };

      # Read component
      read = {
        replicas = 1;
      };

      # Write component
      write = {
        replicas = 1;
        persistence = {
          enabled = true;
          size = config.services.quadnix.loki-deploy.storage.size;
        };
      };

      # Gateway
      gateway = {
        enabled = true;
        replicas = 1;
      };

      # Monitoring
      monitoring = {
        selfMonitoring = {
          enabled = true;
          grafanaAgent = {
            installOperator = false;
          };
        };
        serviceMonitor = {
          enabled = true;
        };
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

    # Loki ServiceMonitor for Prometheus
    environment.etc."loki/servicemonitor.yaml".text = lib.generators.toYAML {} {
      apiVersion: monitoring.coreos.com/v1
      kind: ServiceMonitor
      metadata:
        name: loki
        namespace: loki
        labels:
          app: loki
      spec:
        selector:
          matchLabels:
            app: loki
        endpoints:
        - port: http-metrics
          path: /metrics
          interval: 30s
          scrapeTimeout: 10s
    };
  };
}