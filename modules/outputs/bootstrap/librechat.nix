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
      replicas = 1;
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
          securityContext = {
            fsGroup = 999;
            runAsUser = 999;
            runAsGroup = 999;
            seccompProfile = {
              type = "RuntimeDefault";
            };
          };
          tolerations = [
            {
              key = "node.kubernetes.io/not-ready";
              operator = "Exists";
              effect = "NoExecute";
              tolerationSeconds = 300;
            }
            {
              key = "node.kubernetes.io/unreachable";
              operator = "Exists";
              effect = "NoExecute";
              tolerationSeconds = 300;
            }
          ];
          containers = [
            {
              name = "mongodb";
              image = "mongo:7.0";
              imagePullPolicy = "IfNotPresent";
              ports = [
                {
                  name = "mongodb";
                  containerPort = 27017;
                  protocol = "TCP";
                }
              ];
              volumeMounts = [
                {
                  name = "mongodb-data";
                  mountPath = "/data/db";
                }
              ];
              resources = {
                requests = {
                  memory = "64Mi";
                  cpu = "10m";
                };
                limits = {
                  memory = "256Mi";
                  cpu = "200m";
                };
              };
              securityContext = {
                runAsNonRoot = true;
                allowPrivilegeEscalation = false;
                readOnlyRootFilesystem = false;
                capabilities = {
                  drop = ["ALL"];
                };
              };
            }
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
                  name = "JWT_SECRET";
                  value = "librechat-dev-secret-change-in-production";
                }
                {
                  name = "ALLOW_REGISTRATION";
                  value = "false";
                }
                {
                  name = "ALLOW_EMAIL_LOGIN";
                  value = "true";
                }
                {
                  name = "MONGO_INITDB_DATABASE";
                  value = "librechat";
                }
                {
                  name = "MONGO_URI";
                  value = "mongodb://127.0.0.1:27017/librechat";
                }
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
                  memory = "32Mi";
                  cpu = "5m";
                };
                limits = {
                  memory = "512Mi";
                  cpu = "200m";
                };
              };
              livenessProbe = {
                httpGet = {
                  path = "/";
                  port = 3080;
                };
                initialDelaySeconds = 60;
                periodSeconds = 15;
                timeoutSeconds = 5;
                failureThreshold = 10;
              };
              readinessProbe = {
                httpGet = {
                  path = "/";
                  port = 3080;
                };
                initialDelaySeconds = 30;
                periodSeconds = 10;
                timeoutSeconds = 3;
                failureThreshold = 10;
              };
              volumeMounts = [
                {
                  name = "config";
                  mountPath = "/app/librechat.yaml";
                  subPath = "librechat.yaml";
                }
                {
                  name = "logs";
                  mountPath = "/app/api/logs";
                }
              ];
              securityContext = {
                runAsNonRoot = true;
                allowPrivilegeEscalation = false;
                readOnlyRootFilesystem = false;
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
            {
              name = "logs";
              emptyDir = {
                sizeLimit = "100Mi";
              };
            }
            {
              name = "mongodb-data";
              persistentVolumeClaim = {
                claimName = "librechat-mongodb-data";
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

  pvc = {
    apiVersion = "v1";
    kind = "PersistentVolumeClaim";
    metadata = {
      name = "librechat-mongodb-data";
      namespace = "librechat";
    };
    spec = {
      storageClassName = "ceph-block";
      accessModes = ["ReadWriteOnce"];
      resources = {
        requests = {
          storage = "1Gi";
        };
      };
    };
  };

  manifests = {
    "19-librechat-namespace.yaml" = render.writeOne "19-librechat-namespace" namespace;
    "19a-librechat-configmap.yaml" = render.writeOne "19a-librechat-configmap" configMap;
    "19b-librechat-pvc.yaml" = render.writeOne "19b-librechat-pvc" pvc;
    "19c-librechat-deployment.yaml" = render.writeOne "19c-librechat-deployment" deployment;
    "19d-librechat-service.yaml" = render.writeOne "19d-librechat-service" service;
    "19e-librechat-ingress.yaml" = render.writeOne "19e-librechat-ingress" ingress;
  };
in {
  inherit manifests;
}