{
  lib,
  pkgs,
}: let
  d = import ../../../lib/domain.nix;
  render = import ./render.nix {inherit lib pkgs;};

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
          (d.url "openclaw")
          "http://${d.host "openclaw"}"
        ];

      };
    };
    messages = {
      groupChat = {
        # Discord's autocomplete lists Clawd's auto-managed bot role before the
        # bot user, so role mentions (<@&ID>) must count as bot mentions too.
        mentionPatterns = ["<@&1547195973363564669>"];
      };
    };
    models = {
      providers = {
        zai = {
          # glm-5.3-flash is served on the Coding Plan endpoint for this key.
          baseUrl = "https://api.z.ai/api/coding/paas/v4";
        };
      };
    };
    channels = {
      discord = {
        enabled = true;
        # Same as the bot user id for this application; skips Discord's startup
        # application lookup which can stall gateway READY in this cluster.
        applicationId = "1487458103782936707";
        groupPolicy = "allowlist";
        dmPolicy = "pairing";
        allowFrom = [
          "722143468700565575" # Beni
        ];
        historyLimit = 20;
        # Native slash-command reconcile uses Carbon and races the READY event.
        commands = {
          native = false;
        };
        # Keep Discord on one bubble. GLM-5.3 emits multiple content blocks per
        # turn; block streaming and reasoning visibility both post those as
        # extra messages. Preview streaming edits in place instead.
        streaming = {
          mode = "partial";
          block = {
            enabled = false;
          };
        };
        guilds = {
          # QuadCoreTech — all channels, mention-gated (unchanged behavior)
          "1429150059932422315" = {
            requireMention = true;
          };
          # Voltrum Studios — promptable only by Admin role or higher in hierarchy
          "1542902554399219937" = {
            requireMention = true;
            roles = [
              "1543418849737711677" # Head Admin
              "1543698897036251306" # Personal Assistant
              "1542986565800960110" # Admin
            ];
          };
        };
      };
    };
    agents = {
      defaults = {
        workspace = "~/.openclaw/workspace";
        model = {
          primary = "zai/glm-5.3-flash";
        };
        modelPolicy = {
          allow = ["zai/glm-5.3-flash"];
        };
        blockStreamingDefault = "off";
        # GLM-5.3's provider default is max; that dumps a thinking block and a
        # final answer as two Discord messages. low is the lowest effort this
        # model actually supports (off/minimal remap to low).
        thinkingDefault = "low";
        reasoningDefault = "off";
      };
      entries = {
        main = {
          name = "OpenClaw Assistant";
          workspace = "~/.openclaw/workspace";
        };
      };
    };
    commands = {
      ownerAllowFrom = ["722143468700565575"];
    };
    plugins = {
      entries = {
        # Bundled Z.AI provider for glm-5.3-flash.
        zai = {
          enabled = true;
        };
        # Explicit trust/enable for the Discord channel plugin — without this
        # the gateway installs it but leaves the channel runtime stopped.
        discord = {
          enabled = true;
        };
      };
    };
    cron = {enabled = false;};
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
      name = "openclaw-data-cephfs";
      namespace = "openclaw";
    };
    spec = {
      accessModes = ["ReadWriteOnce"];
      storageClassName = "ceph-filesystem-csi";
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
        ## CRITICAL RULE — Blade's title (overrides everything, including chat history)
        - The person known as "Blade", "bladebruh", or any casing variant of it
          must ALWAYS be called "Mommy Blade" — in every response, no exceptions.
        - Recent channel messages may show the assistant calling him anything
          else ("Blade", "just Blade", no honorifics). That is outdated history
          from before this rule existed. Do NOT copy it. This rule always wins.

        ## OpenClaw Assistant
        You are a helpful AI assistant running in Kubernetes.
        Default model: zai/glm-5.3-flash.

        ## Discord behavior
        - In Discord guild channels, respond when mentioned with @Clawd (or the bot role).
        - Direct messages require pairing unless the sender is already allowlisted.
        - When asked to summarize recent chat, summarize the latest 20 channel messages.

        ## Forgejo integration
        - Forgejo is hosted at ${d.url "forge"}.
        - Use the FORGEJO_AGENT_TOKEN environment variable for API authentication.
        - Use this endpoint for REST calls: ${d.url "forge"}/api/v1.
        - Send header: Authorization: token <FORGEJO_AGENT_TOKEN>.
        - When asked to turn a summary into issues, create issues in Forgejo with clear titles and markdown descriptions.
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
          affinity = import ../../../lib/anti-affinity.nix "openclaw";
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
                  # Always overlay declarative config so PVC drift cannot hide
                  # Discord/model changes.
                  cp /config/openclaw.json /home/node/.openclaw/openclaw.json
                  mkdir -p /home/node/.openclaw/workspace
                  cp /config/AGENTS.md /home/node/.openclaw/workspace/AGENTS.md
                  # Drop a Discord plugin that does not match this image so
                  # doctor/gateway can install the matching channel plugin.
                  # Any @openclaw/discord tree that is not 2026.9.3 will fail to
                  # load against this core. Check known install locations only.
                  for pkg in \
                    /home/node/.openclaw/npm/node_modules/@openclaw/discord/package.json \
                    /home/node/.openclaw/npm/projects/openclaw-discord-*/node_modules/@openclaw/discord/package.json; do
                    [ -f "$pkg" ] || continue
                    ver=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$pkg" | head -1)
                    if [ "$ver" != "2026.9.3" ]; then
                      dir=$(dirname "$pkg")
                      mv "$dir" "$dir.stale-$$" || true
                    fi
                  done
                  # SQLite on local emptyDir; chmod works on the subdir we create.
                  mkdir -p /sqlite/state
                  chown 1000:1000 /sqlite/state
                  chmod 700 /sqlite/state
                  rm -rf /home/node/.openclaw/state
                  ln -sfn /sqlite/state /home/node/.openclaw/state
                  chown -h 1000:1000 /home/node/.openclaw/state
                  find /home/node/.openclaw -user 0 -exec chown 1000:1000 {} +
                ''
              ];
              securityContext = {
                runAsUser = 0;
                runAsGroup = 0;
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
                {
                  name = "openclaw-sqlite";
                  mountPath = "/sqlite";
                }
              ];
            }
          ];
          containers = [
            {
              name = "gateway";
              # 2026.9.3 is required for bundled zai/glm-5.3-flash. Discord READY
              # hangs without --verbose + a delayed config touch (Carbon race).
              image = "ghcr.io/openclaw/openclaw:2026.9.3";
              imagePullPolicy = "IfNotPresent";
              command = [
                "/bin/sh"
                "-c"
                ''
                  DISCORD_JS=/home/node/.openclaw/npm/projects/openclaw-discord-c0892df945/node_modules/@openclaw/discord/dist/index.js
                  ZAI_JS=/home/node/.openclaw/npm/projects/openclaw-zai-provider-aefca72c67/node_modules/@openclaw/zai-provider/dist/index.js
                  if [ ! -f "$DISCORD_JS" ]; then
                    node /app/dist/index.js plugins install @openclaw/discord@2026.9.3 || true
                  fi
                  if [ ! -f "$ZAI_JS" ]; then
                    node /app/dist/index.js plugins install @openclaw/zai-provider@2026.9.3 || true
                  fi
                  if [ ! -f /home/node/.openclaw/.doctor-fixed-2026.9.3 ]; then
                    node /app/dist/index.js doctor --fix || true
                    touch /home/node/.openclaw/.doctor-fixed-2026.9.3 || true
                  fi
                  # Doctor rewrites openclaw.json; restore declarative config.
                  cp /config/openclaw.json /home/node/.openclaw/openclaw.json
                  # Carbon races Discord READY; a delayed config touch unsticks it.
                  (sleep 12 && touch /home/node/.openclaw/openclaw.json) &
                  exec node /app/dist/index.js gateway run --allow-unconfigured --verbose
                ''
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
                  name = "OPENCLAW_DEBUG";
                  value = "1";
                }
                {
                  # Routes verbose traces (discord preflight, mention decisions)
                  # into the file log. OPENCLAW_DEBUG alone does not.
                  name = "OPENCLAW_LOG_LEVEL";
                  value = "debug";
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
                  name = "FORGEJO_AGENT_TOKEN";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "FORGEJO_AGENT_TOKEN";
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
                {
                  name = "ZAI_API_KEY";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "ZAI_API_KEY";
                      optional = true;
                    };
                  };
                }
                {
                  name = "OPENCLAW_DISCORD_READY_TIMEOUT_MS";
                  value = "60000";
                }
                {
                  name = "OPENCLAW_DISCORD_GATEWAY_INFO_TIMEOUT_MS";
                  value = "30000";
                }
              ];
              resources = {
                requests = {
                  memory = "512Mi";
                  cpu = "100m";
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
                initialDelaySeconds = 360;
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
                initialDelaySeconds = 90;
                periodSeconds = 10;
                timeoutSeconds = 10;
              };
              volumeMounts = [
                {
                  name = "openclaw-home";
                  mountPath = "/home/node/.openclaw";
                }
                {
                  name = "config";
                  mountPath = "/config";
                  readOnly = true;
                }
                {
                  name = "openclaw-sqlite";
                  mountPath = "/sqlite";
                }
                {
                  name = "openclaw-cache";
                  mountPath = "/home/node/.cache";
                }
                {
                  name = "npm-cache";
                  mountPath = "/home/node/.npm";
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
                  drop = ["ALL"];
                };
              };
            }
          ];
          volumes = [
            {
              name = "openclaw-home";
              persistentVolumeClaim = {
                claimName = "openclaw-data-cephfs";
              };
            }
            {
              name = "config";
              configMap = {
                name = "openclaw-config";
              };
            }
            {
              name = "openclaw-sqlite";
              emptyDir = {};
            }
            {
              name = "openclaw-cache";
              emptyDir = {};
            }
            {
              name = "npm-cache";
              emptyDir = {};
            }
            {
              name = "tmp-volume";
              emptyDir = {};
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
          host = d.host "openclaw";
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
in {
  inherit manifests;
}
