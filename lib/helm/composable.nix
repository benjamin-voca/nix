# Composable Nix functions for building Kubernetes manifests
# This library provides composable, reusable functions for creating k8s resources
#
# Usage:
#   let
#     composable = import ./lib/helm/composable.nix { inherit pkgs; };
#   in
#     composable.mkNamespace "my-namespace" {}
{pkgs ? throw "pkgs is required"}: let
  inherit (pkgs) lib;

  # ===========================================================================
  # Base Kubernetes Resource Builders (defined first for forward references)
  # ===========================================================================

  mkNamespace = name: {
    labels ? {},
    annotations ? {},
  }: {
    apiVersion = "v1";
    kind = "Namespace";
    metadata = {
      inherit name;
      inherit labels;
      inherit annotations;
    };
  };

  mkConfigMap = name: namespace: data: {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      inherit name;
      namespace = namespace;
      inherit data;
    };
  };

  mkSecret = name: namespace: stringData: {
    apiVersion = "v1";
    kind = "Secret";
    metadata = {
      inherit name;
      namespace = namespace;
    };
    type = "Opaque";
    inherit stringData;
  };

  mkPVC = name: namespace: {
    storageClass ? "ceph-block",
    accessModes ? ["ReadWriteOnce"],
    size ? "10Gi",
  }: {
    apiVersion = "v1";
    kind = "PersistentVolumeClaim";
    metadata = {
      inherit name;
      namespace = namespace;
    };
    spec = {
      accessModes = accessModes;
      storageClassName = storageClass;
      resources = {
        requests = {
          storage = size;
        };
      };
    };
  };

  mkServiceBase = name: namespace: type: ports: {
    selector ? {},
    annotations ? {},
  }: {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      inherit name;
      namespace = namespace;
      inherit annotations;
    };
    spec = {
      inherit type;
      inherit ports;
      inherit selector;
    };
  };

  mkNodePortService = name: namespace: targetPort: nodePort: selector:
    mkServiceBase name namespace "NodePort"
    [
      {
        port = targetPort;
        targetPort = targetPort;
        nodePort = nodePort;
        protocol = "TCP";
      }
    ]
    {inherit selector;};

  # ===========================================================================
  # ArgoCD Application Builders
  # ===========================================================================

  mkArgoHelmApp = {
    name,
    namespace,
    chart,
    repoURL,
    targetRevision,
    parameters ? [],
    values ? "",
    valueFiles ? [],
    finalizers ? ["resources-finalizer.argocd.argoproj.io"],
    ignoreDifferences ? [],
  }: let
    baseSpec = {
      apiVersion = "argoproj.io/v1alpha1";
      kind = "Application";
      metadata = {
        inherit name;
        namespace = "argocd";
        inherit finalizers;
      };
      spec = {
        project = "default";
        source =
          {
            inherit chart repoURL targetRevision;
          }
          // lib.optionalAttrs (parameters != []) {inherit parameters;}
          // lib.optionalAttrs (values != "") {inherit values;}
          // lib.optionalAttrs (valueFiles != []) {inherit valueFiles;};
        destination = {
          server = "https://kubernetes.default.svc";
          inherit namespace;
        };
        syncPolicy = {
          automated = {
            prune = true;
            selfHeal = true;
          };
        };
      };
    };
  in
    baseSpec
    // lib.optionalAttrs (ignoreDifferences != []) {
      spec = baseSpec.spec // {ignoreDifferences = ignoreDifferences;};
    };

  mkArgoHelmAppFromChart = chartInfo:
    mkArgoHelmApp {
      name = chartInfo.name;
      namespace = chartInfo.namespace;
      chart = chartInfo.chart;
      repoURL = chartInfo.repoURL;
      targetRevision = chartInfo.targetRevision;
      parameters = chartInfo.parameters or [];
      values = chartInfo.values or "";
      valueFiles = chartInfo.valueFiles or [];
      finalizers = chartInfo.finalizers or ["resources-finalizer.argocd.argoproj.io"];
      ignoreDifferences = chartInfo.ignoreDifferences or [];
    };

  # ===========================================================================
  # CNPG (CloudNativePG) Utilities
  # ===========================================================================

  mkCNPGClusterRef = clusterName: namespace: {
    host = "${clusterName}.${namespace}.svc.cluster.local";
    port = 5432;
    database = "app";
    username = "app";
  };

  mkCNPGConnectionString = clusterRef: "postgres://${clusterRef.username}@${clusterRef.host}:${toString clusterRef.port}/${clusterRef.database}";

  # ===========================================================================
  # Cloudflared / Tunnel Configuration
  # ===========================================================================

  mkCloudflaredConfig = {
    tunnel,
    credentialsFile ? "/etc/cloudflared/creds/credentials.json",
    metrics ? "0.0.0.0:2000",
    no-autoupdate ? true,
  }: ingressList: {
    inherit tunnel;
    credentials-file = credentialsFile;
    inherit metrics;
    no-autoupdate = no-autoupdate;
    ingress = ingressList;
  };

  mkCloudflaredIngress = hostname: service: {
    inherit hostname;
    inherit service;
  };

  mkCloudflaredDefaultIngress = service: mkCloudflaredIngress null service;

  # ===========================================================================
  # Forgejo Actions Runner
  # ===========================================================================

  mkForgejoRunnerSA = namespace: {
    apiVersion = "v1";
    kind = "ServiceAccount";
    metadata = {
      name = "forgejo-actions";
      namespace = namespace;
    };
  };

  mkForgejoRunnerSecret = name: namespace: tokenPlaceholder: {
    apiVersion = "v1";
    kind = "Secret";
    metadata = {
      inherit name;
      namespace = namespace;
    };
    type = "Opaque";
    stringData = {
      token = tokenPlaceholder;
    };
  };

  mkForgejoRunnerStatefulSet = {
    name ? "forgejo-actions",
    namespace ? "forgejo",
    replicas ? 2,
    forgejoInstanceUrl ? "https://forge.quadtech.dev",
    runnerTokenSecret ? "forgejo-runner-token",
    runnerName ? "k8s-runner",
    runnerLabels ? "ubuntu-latest,linux,x86_64,self-hosted",
    dindImage ? "docker:28.3.3-dind",
    actRunnerImage ? "code.forgejo.org/forgejo/runner:3.5.0",
  }: let
    container-act-runner = {
      name = "act-runner";
      image = actRunnerImage;
      env = [
        {
          name = "GITEA_INSTANCE_URL";
          value = forgejoInstanceUrl;
        }
        {
          name = "GITEA_RUNNER_TOKEN";
          valueFrom = {
            secretKeyRef = {
              name = runnerTokenSecret;
              key = "token";
            };
          };
        }
        {
          name = "GITEA_RUNNER_LABELS";
          value = runnerLabels;
        }
        {
          name = "GITEA_RUNNER_NAME";
          value = runnerName;
        }
        {
          name = "DOCKER_HOST";
          value = "tcp://localhost:2375";
        }
      ];
      command = [
        "/bin/sh"
        "-c"
        ''
                    cd /data
                    cat > config.yaml << 'CFGEof'
          runner:
            name: ${runnerName}
            url: ${forgejoInstanceUrl}
            token: $$GITEA_RUNNER_TOKEN
            labels:
              - ubuntu-latest
              - linux
              - x86_64
              - self-hosted
          docker:
            host: tcp://localhost:2375
          CFGEof
                    if [ ! -f .runner ]; then
                      act_runner register --instance $${forgejoInstanceUrl} --token $${runnerTokenSecret} --name $${runnerName} --labels $${runnerLabels} --no-interactive
                    fi
                    act_runner daemon --config config.yaml
        ''
      ];
      volumeMounts = [
        {
          name = "runner-data";
          mountPath = "/data";
        }
      ];
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
        limits = {
          cpu = "1000m";
          memory = "1Gi";
        };
      };
    };

    container-dind = {
      name = "dind";
      image = dindImage;
      args = ["dockerd" "--host=tcp://0.0.0.0:2375"];
      ports = [{containerPort = 2375;}];
      securityContext = {privileged = true;};
      volumeMounts = [
        {
          name = "runner-data";
          mountPath = "/var/lib/docker";
        }
      ];
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
        limits = {
          cpu = "2000m";
          memory = "2Gi";
        };
      };
    };
  in {
    apiVersion = "apps/v1";
    kind = "StatefulSet";
    metadata = {
      inherit name;
      namespace = namespace;
    };
    spec = {
      serviceName = name;
      inherit replicas;
      selector = {matchLabels = {"app.kubernetes.io/name" = name;};};
      template = {
        metadata = {labels = {"app.kubernetes.io/name" = name;};};
        spec = {
          serviceAccountName = "forgejo-actions";
          containers = [container-act-runner container-dind];
          volumes = [
            {
              name = "runner-data";
              emptyDir = {};
            }
          ];
        };
      };
    };
  };

  # ===========================================================================
  # Cloudflared Deployment
  # ===========================================================================

  mkCloudflaredDeployment = {
    name ? "cloudflared",
    namespace ? "cloudflared",
    image ? "cloudflare/cloudflared:latest",
    configPath ? "/etc/cloudflared/config/config.yaml",
    credentialsSecret ? "cloudflared-credentials",
    replicas ? 1,
  }: {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      inherit name;
      namespace = namespace;
      labels = {app = name;};
    };
    spec = {
      inherit replicas;
      selector = {matchLabels = {app = name;};};
      template = {
        metadata = {labels = {app = name;};};
        spec = {
          hostNetwork = true;
          containers = [
            {
              inherit name image;
              command = ["cloudflared" "tunnel" "--config" configPath "run"];
              volumeMounts = [
                {
                  name = "config";
                  mountPath = "/etc/cloudflared/config";
                  readOnly = true;
                }
                {
                  name = "creds";
                  mountPath = "/etc/cloudflared/creds";
                  readOnly = true;
                }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "128Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "256Mi";
                };
              };
            }
          ];
          volumes = [
            {
              name = "config";
              configMap = {
                name = "cloudflared-config";
                items = [
                  {
                    key = "config.yaml";
                    path = "config.yaml";
                  }
                ];
              };
            }
            {
              name = "creds";
              secret = {secretName = credentialsSecret;};
            }
          ];
        };
      };
    };
  };

  # ===========================================================================
  # MetalLB CRDs
  # ===========================================================================

  mkMetallbIPAddressPool = name: namespace: addresses: autoAssign: {
    apiVersion = "metallb.io/v1beta1";
    kind = "IPAddressPool";
    metadata = {
      inherit name;
      namespace = namespace;
    };
    spec = {inherit addresses autoAssign;};
  };

  mkMetallbL2Advertisement = name: namespace: ipAddressPools: {
    apiVersion = "metallb.io/v1beta1";
    kind = "L2Advertisement";
    metadata = {
      inherit name;
      namespace = namespace;
    };
    spec = {inherit ipAddressPools;};
  };

  mkMetallbCRDs = {
    poolName ? "default",
    namespace ? "metallb",
    addresses ? ["192.168.1.240-192.168.1.250"],
    autoAssign ? true,
  }: [
    (mkMetallbIPAddressPool poolName namespace addresses autoAssign)
    (mkMetallbL2Advertisement poolName namespace [poolName])
  ];

  # ===========================================================================
  # Common Presets
  # ===========================================================================

  smallResources = {
    requests = {
      cpu = "50m";
      memory = "64Mi";
    };
    limits = {
      cpu = "200m";
      memory = "256Mi";
    };
  };

  mediumResources = {
    requests = {
      cpu = "100m";
      memory = "128Mi";
    };
    limits = {
      cpu = "500m";
      memory = "512Mi";
    };
  };

  largeResources = {
    requests = {
      cpu = "500m";
      memory = "512Mi";
    };
    limits = {
      cpu = "2000m";
      memory = "2Gi";
    };
  };

  defaultArgoSyncPolicy = {
    automated = {
      prune = true;
      selfHeal = true;
    };
  };

  # ===========================================================================
  # YAML Serialization Helpers
  # ===========================================================================

  toYAMLString = value: builtins.toJSON value;

  writeManifest = name: value: pkgs.writeText "${name}.yaml" (builtins.toJSON value);

  writeManifests = manifests: let
    manifestStrings = map (m: builtins.toJSON m) manifests;
    separator = "---";
    combined = lib.concatStringsSep "
${separator}
" manifestStrings;
  in
    pkgs.writeText "manifests.yaml" combined;

  # ===========================================================================
  # Preset: Shared Application Patterns
  # ===========================================================================

  composeChartValues = overlays:
    lib.foldl' lib.recursiveUpdate {} overlays;

  presetWithCNPG = clusterRef: extraValues: let
    dbConfig = {
      database = {
        DB_TYPE = "postgres";
        HOST = "${clusterRef.host}:${toString clusterRef.port}";
        NAME = clusterRef.database;
        USER = clusterRef.username;
        PASSWD = "REPLACE_ME";
        SSL_MODE = "disable";
      };
    };
  in
    composeChartValues [dbConfig extraValues];

  presetWithLonghorn = {
    persistence = {
      enabled = true;
      storageClass = "ceph-block";
    };
  };

  presetWithIngress = {
    ingress = {
      enabled = true;
      className = "nginx";
    };
  };
in {
  inherit mkNamespace mkConfigMap mkSecret mkPVC mkServiceBase mkNodePortService;
  inherit mkArgoHelmApp mkArgoHelmAppFromChart;
  inherit mkCNPGClusterRef mkCNPGConnectionString;
  inherit mkCloudflaredConfig mkCloudflaredIngress mkCloudflaredDefaultIngress;
  inherit mkForgejoRunnerSA mkForgejoRunnerSecret mkForgejoRunnerStatefulSet;
  inherit mkCloudflaredDeployment;
  inherit mkMetallbIPAddressPool mkMetallbL2Advertisement mkMetallbCRDs;
  inherit smallResources mediumResources largeResources defaultArgoSyncPolicy;
  inherit toYAMLString writeManifest writeManifests composeChartValues;
  inherit presetWithCNPG presetWithLonghorn presetWithIngress;
}
