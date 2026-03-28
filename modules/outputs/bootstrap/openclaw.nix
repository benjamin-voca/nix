{ lib, pkgs }:

let
  render = import ./render.nix { inherit lib pkgs; };

  openclawConfigJson = builtins.toJSON {
    gateway = {
      mode = "local";
      bind = "lan";
      port = 18789;
      auth = {
        mode = "token";
      };
      trustedProxies = [
        "10.0.0.0/8"
        "192.168.0.0/16"
        "172.16.0.0/12"
      ];
      controlUi = {
        enabled = true;
        allowedOrigins = [
          "https://openclaw.quadtech.dev"
          "http://openclaw.quadtech.dev"
        ];
        dangerouslyDisableDeviceAuth = true;
      };
    };
    channels = {
      discord = {
        enabled = true;
        token = {
          source = "env";
          provider = "default";
          id = "DISCORD_BOT_TOKEN";
        };
      };
    };
    agents = {
      defaults = {
        workspace = "~/.openclaw/workspace";
      };
      list = [
        {
          id = "default";
          name = "OpenClaw Assistant";
          workspace = "~/.openclaw/workspace";
        }
      ];
    };
    cron = { enabled = false; };
  };

  namespace = {
    apiVersion = "v1";
    kind = "Namespace";
    metadata = {
      name = "openclaw";
      labels = {
        "app.kubernetes.io/name" = "openclaw";
      };
    };
  };

  pvc = {
    apiVersion = "v1";
    kind = "PersistentVolumeClaim";
    metadata = {
      name = "openclaw-data";
      namespace = "openclaw";
    };
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

  configMap = {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "openclaw-config";
      namespace = "openclaw";
    };
    data = {
      "openclaw.json" = openclawConfigJson;
      "AGENTS.md" = ''
        ## OpenClaw Assistant
        You are a helpful AI assistant running in Kubernetes.
      '';
    };
  };

  deployment = {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      name = "openclaw";
      namespace = "openclaw";
      labels = {
        app = "openclaw";
      };
    };
    spec = {
      replicas = 1;
      selector = {
        matchLabels = {
          app = "openclaw";
        };
      };
      strategy = {
        type = "Recreate";
      };
      template = {
        metadata = {
          labels = {
            app = "openclaw";
          };
        };
        spec = {
          automountServiceAccountToken = false;
          securityContext = {
            fsGroup = 1000;
            seccompProfile = {
              type = "RuntimeDefault";
            };
          };
          initContainers = [
            {
              name = "init-config";
              image = "busybox:1.37";
              imagePullPolicy = "IfNotPresent";
              command = [
                "sh"
                "-c"
                ''
                  cp /config/openclaw.json /home/node/.openclaw/openclaw.json
                  mkdir -p /home/node/.openclaw/workspace
                  cp /config/AGENTS.md /home/node/.openclaw/workspace/AGENTS.md
                ''
              ];
              securityContext = {
                runAsUser = 1000;
                runAsGroup = 1000;
              };
              resources = {
                requests = {
                  memory = "32Mi";
                  cpu = "50m";
                };
                limits = {
                  memory = "64Mi";
                  cpu = "100m";
                };
              };
              volumeMounts = [
                {
                  name = "openclaw-home";
                  mountPath = "/home/node/.openclaw";
                }
                {
                  name = "config";
                  mountPath = "/config";
                }
              ];
            }
          ];
          containers = [
            {
              name = "gateway";
              image = "ghcr.io/openclaw/openclaw:slim";
              imagePullPolicy = "IfNotPresent";
              command = [
                "node"
                "/app/dist/index.js"
                "gateway"
                "run"
                "--allow-unconfigured"
              ];
              ports = [
                {
                  name = "gateway";
                  containerPort = 18789;
                  protocol = "TCP";
                }
              ];
              env = [
                {
                  name = "HOME";
                  value = "/home/node";
                }
                {
                  name = "OPENCLAW_CONFIG_DIR";
                  value = "/home/node/.openclaw";
                }
                {
                  name = "NODE_ENV";
                  value = "production";
                }
                {
                  name = "OPENCLAW_GATEWAY_TOKEN";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "OPENCLAW_GATEWAY_TOKEN";
                    };
                  };
                }
                {
                  name = "DISCORD_BOT_TOKEN";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "DISCORD_BOT_TOKEN";
                      optional = true;
                    };
                  };
                }
                {
                  name = "OPENCLAW_DISCORD_SERVER_ID";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "OPENCLAW_DISCORD_SERVER_ID";
                      optional = true;
                    };
                  };
                }
                {
                  name = "OPENCLAW_BENI_DISCORD_ID";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "OPENCLAW_BENI_DISCORD_ID";
                      optional = true;
                    };
                  };
                }
                {
                  name = "MINIMAX_API_KEY";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "MINIMAX_API_KEY";
                      optional = true;
                    };
                  };
                }
              ];
              resources = {
                requests = {
                  memory = "512Mi";
                  cpu = "250m";
                };
                limits = {
                  memory = "2Gi";
                  cpu = "1";
                };
              };
              livenessProbe = {
                exec = {
                  command = [
                    "node"
                    "-e"
                    "require('http').get('http://127.0.0.1:18789/healthz', r => process.exit(r.statusCode < 400 ? 0 : 1)).on('error', () => process.exit(1))"
                  ];
                };
                initialDelaySeconds = 60;
                periodSeconds = 30;
                timeoutSeconds = 10;
              };
              readinessProbe = {
                exec = {
                  command = [
                    "node"
                    "-e"
                    "require('http').get('http://127.0.0.1:18789/readyz', r => process.exit(r.statusCode < 400 ? 0 : 1)).on('error', () => process.exit(1))"
                  ];
                };
                initialDelaySeconds = 15;
                periodSeconds = 10;
                timeoutSeconds = 5;
              };
              volumeMounts = [
                {
                  name = "openclaw-home";
                  mountPath = "/home/node/.openclaw";
                }
                {
                  name = "tmp-volume";
                  mountPath = "/tmp";
                }
              ];
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 1000;
                runAsGroup = 1000;
                allowPrivilegeEscalation = false;
                readOnlyRootFilesystem = true;
                capabilities = {
                  drop = [ "ALL" ];
                };
              };
            }
          ];
          volumes = [
            {
              name = "openclaw-home";
              persistentVolumeClaim = {
                claimName = "openclaw-data";
              };
            }
            {
              name = "config";
              configMap = {
                name = "openclaw-config";
              };
            }
            {
              name = "tmp-volume";
              emptyDir = { };
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
      name = "openclaw";
      namespace = "openclaw";
    };
    spec = {
      type = "ClusterIP";
      ports = [
        {
          port = 18789;
          targetPort = 18789;
          protocol = "TCP";
        }
      ];
      selector = {
        app = "openclaw";
      };
    };
  };

  ingress = {
    apiVersion = "networking.k8s.io/v1";
    kind = "Ingress";
    metadata = {
      name = "openclaw";
      namespace = "openclaw";
      annotations = {
        "nginx.ingress.kubernetes.io/ssl-redirect" = "false";
        "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
        "nginx.ingress.kubernetes.io/proxy-body-size" = "50m";
        "nginx.ingress.kubernetes.io/websocket-services" = "openclaw";
      };
    };
    spec = {
      ingressClassName = "nginx";
      rules = [
        {
          host = "openclaw.quadtech.dev";
          http = {
            paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend = {
                  service = {
                    name = "openclaw";
                    port = {
                      number = 18789;
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
    "17-openclaw-namespace.yaml" = render.writeOne "17-openclaw-namespace" namespace;
    "17a-openclaw-pvc.yaml" = render.writeOne "17a-openclaw-pvc" pvc;
    "17b-openclaw-configmap.yaml" = render.writeOne "17b-openclaw-configmap" configMap;
    "17c-openclaw-deployment.yaml" = render.writeOne "17c-openclaw-deployment" deployment;
    "17d-openclaw-service.yaml" = render.writeOne "17d-openclaw-service" service;
    "17e-openclaw-ingress.yaml" = render.writeOne "17e-openclaw-ingress" ingress;
  };
in
{
  inherit manifests;
}
