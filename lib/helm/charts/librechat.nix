{helmLib}: {
  librechat = helmLib.buildChart {
    name = "librechat";
    chart = helmLib.kubelib.downloadHelmChart {
      repo = "https://registry.librechat.ai/helm";
      chart = "librechat";
      version = "1.0.0";
      chartHash = "sha256-temporary-placeholder";
    };
    namespace = "librechat";
    values = {
      replicaCount = 2;

      image = {
        repository = "registry.librechat.ai/danny-avila/librechat-api";
        tag = "latest";
        pullPolicy = "IfNotPresent";
      };

      service = {
        type = "ClusterIP";
        http = {
          port = 3080;
        };
      };

      ingress = {
        enabled = true;
        className = "nginx";
        annotations = {
          "nginx.ingress.kubernetes.io/proxy-body-size" = "512m";
        };
        hosts = [
          {
            host = "chat.quadtech.dev";
            paths = [
              {
                path = "/";
                pathType = "Prefix";
              }
            ];
          }
        ];
        tls = [];
      };

      resources = {
        requests = {
          cpu = "100m";
          memory = "256Mi";
        };
        limits = {
          cpu = "1000m";
          memory = "1Gi";
        };
      };

      livenessProbe = {
        enabled = true;
        initialDelaySeconds = 30;
        periodSeconds = 10;
        timeoutSeconds = 5;
      };

      readinessProbe = {
        enabled = true;
        initialDelaySeconds = 10;
        periodSeconds = 5;
        timeoutSeconds = 3;
      };

      env = [
        {
          name = "OPENAI_API_KEY";
          valueFrom = {
            secretKeyRef = {
              name = "librechat-api-keys";
              key = "OPENAI_API_KEY";
            };
          };
        }
        {
          name = "MINIMAX_API_KEY";
          valueFrom = {
            secretKeyRef = {
              name = "librechat-api-keys";
              key = "MINIMAX_API_KEY";
            };
          };
        }
      ];

      configmap = {
        data = {
          "librechat.yaml" = ''
            version: 1.3.5
            cache: true
          '';
        };
      };
    };
  };
}