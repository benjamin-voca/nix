{
  lib,
  pkgs,
}: let
  render = import ./render.nix {inherit lib pkgs;};

  namespace = {
    apiVersion = "v1";
    kind = "Namespace";
    metadata = {
      name = "librechat";
      labels = {
        "app.kubernetes.io/name" = "librechat";
      };
    };
  };

  configMap = {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "librechat-config";
      namespace = "librechat";
    };
    data = {
      "librechat.yaml" = ''
        version: 1.3.5
        cache: true
      '';
    };
  };

  deployment = {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      name = "librechat";
      namespace = "librechat";
      labels = {
        app = "librechat";
      };
    };
    spec = {
      replicas = 2;
      selector = {
        matchLabels = {
          app = "librechat";
        };
      };
      strategy = {
        type = "RollingUpdate";
        rollingUpdate = {
          maxSurge = 0;
          maxUnavailable = 1;
        };
      };
      template = {
        metadata = {
          labels = {
            app = "librechat";
          };
        };
        spec = {
          affinity = import ../../../lib/anti-affinity.nix "librechat";
          securityContext = {
            fsGroup = 1000;
            seccompProfile = {
              type = "RuntimeDefault";
            };
          };
          containers = [
            {
              name = "librechat";
              image = "registry.librechat.ai/danny-avila/librechat-api:latest";
              imagePullPolicy = "IfNotPresent";
              ports = [
                {
                  name = "http";
                  containerPort = 3080;
                  protocol = "TCP";
                }
              ];
              env = [
                {
                  name = "ZHIPU_API_KEY";
                  valueFrom = {
                    secretKeyRef = {
                      name = "librechat-api-keys";
                      key = "ZHIPU_API_KEY";
                      optional = true;
                    };
                  };
                }
                {
                  name = "MINIMAX_API_KEY";
                  valueFrom = {
                    secretKeyRef = {
                      name = "librechat-api-keys";
                      key = "MINIMAX_API_KEY";
                      optional = true;
                    };
                  };
                }
              ];
              resources = {
                requests = {
                  memory = "256Mi";
                  cpu = "100m";
                };
                limits = {
                  memory = "1Gi";
                  cpu = "1000m";
                };
              };
              livenessProbe = {
                httpGet = {
                  path = "/";
                  port = 3080;
                };
                initialDelaySeconds = 30;
                periodSeconds = 10;
                timeoutSeconds = 5;
              };
              readinessProbe = {
                httpGet = {
                  path = "/";
                  port = 3080;
                };
                initialDelaySeconds = 10;
                periodSeconds = 5;
                timeoutSeconds = 3;
              };
              volumeMounts = [
                {
                  name = "config";
                  mountPath = "/app/client/librechat.yaml";
                  subPath = "librechat.yaml";
                }
              ];
              securityContext = {
                runAsNonRoot = false;
                allowPrivilegeEscalation = false;
                readOnlyRootFilesystem = true;
                capabilities = {
                  drop = ["ALL"];
                };
              };
            }
          ];
          volumes = [
            {
              name = "config";
              configMap = {
                name = "librechat-config";
              };
            }
          ];
        };
      };
    };
  };

  service = {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      name = "librechat";
      namespace = "librechat";
    };
    spec = {
      type = "ClusterIP";
      ports = [
        {
          port = 80;
          targetPort = 3080;
          protocol = "TCP";
        }
      ];
      selector = {
        app = "librechat";
      };
    };
  };

  ingress = {
    apiVersion = "networking.k8s.io/v1";
    kind = "Ingress";
    metadata = {
      name = "librechat";
      namespace = "librechat";
      annotations = {
        "nginx.ingress.kubernetes.io/proxy-body-size" = "512m";
      };
    };
    spec = {
      ingressClassName = "nginx";
      rules = [
        {
          host = "chat.quadtech.dev";
          http = {
            paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend = {
                  service = {
                    name = "librechat";
                    port = {
                      number = 80;
                    };
                  };
                };
              }
            ];
          };
        }
      ];
    };
  };

  manifests = {
    "19-librechat-namespace.yaml" = render.writeOne "19-librechat-namespace" namespace;
    "19a-librechat-configmap.yaml" = render.writeOne "19a-librechat-configmap" configMap;
    "19b-librechat-deployment.yaml" = render.writeOne "19b-librechat-deployment" deployment;
    "19c-librechat-service.yaml" = render.writeOne "19c-librechat-service" service;
    "19d-librechat-ingress.yaml" = render.writeOne "19d-librechat-ingress" ingress;
  };
in {
  inherit manifests;
}