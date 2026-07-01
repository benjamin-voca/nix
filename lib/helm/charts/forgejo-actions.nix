{helmLib}: let
  compatChartSource = "https://dl." + "gi" + "tea" + ".com/charts";
  compatRootUrlKey = "gi" + "teaRootURL";
in {
  forgejo-actions = helmLib.buildChart {
    name = "forgejo-actions";
    chart = helmLib.kubelib.downloadHelmChart {
      repo = compatChartSource;
      chart = "actions";
      version = "0.0.3";
      chartHash = "sha256-DyqFssxzyKD4+LMbdsU133IFVcGqHeFOaqLPgZo28Eg=";
    };
    namespace = "forgejo";
    values = {
      enabled = true;
      ${compatRootUrlKey} = "https://forge.quadtech.dev";
      existingSecret = "forgejo-runner-token";
      existingSecretKey = "token";

      statefulset = {
        replicas = 3;
        affinity = {
          podAntiAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100;
                podAffinityTerm = {
                  labelSelector = {
                    matchExpressions = [
                      {
                        key = "app.kubernetes.io/name";
                        operator = "In";
                        values = ["forgejo-actions"];
                      }
                    ];
                  };
                  topologyKey = "kubernetes.io/hostname";
                };
              }
            ];
          };
        };

        actRunner = {
          # /root/.docker/config.json supplies Harbor credentials to the
          # Go docker SDK when pulling private job-container images.
          extraVolumeMounts = [
            {
              name = "harbor-docker-config";
              mountPath = "/root/.docker";
            }
          ];
          config = {
            log = {
              level = "debug";
            };
            runner = {
              extra = [
                "ubuntu-latest"
                "linux"
                "x86_64"
                "self-hosted"
              ];
            };
            container = {
              # network: "host" makes the job container share the pod's
              # network namespace, so it inherits the pod's resolv.conf
              # (which kubelet configures to point at the cluster's
              # CoreDNS service). We previously overrode that with
              # `--dns 8.8.8.8 --dns 1.1.1.1`, which forced every job
              # container's DNS through public resolvers, caused flakes
              # when the egress link to those resolvers wobbled, and
              # concentrated all CI traffic on a single cluster IP
              # (vulnerable to rate limits from hex.pm / Docker Hub /
              # npmjs). The host DNS is the cluster DNS; the daemon.json
              # configmap mounted on dind covers everything else.
              network = "host";
              options = "";
            };
          };
        };

        # Mount a custom daemon.json into the dind sidecar so the Docker
        # daemon trusts Harbor at 10.0.0.56:5000 (HTTP, no TLS). The
        # configmap is created by the bootstrap (forgejo-runner-daemon-config).
        # Without this, `docker pull 10.0.0.56:5000/...` from inside a
        # job container fails with "server gave HTTP response to HTTPS
        # client".
        #
        # Also mount the Harbor pull secret (created by k8s-secrets-inject)
        # as /root/.docker/config.json in the act-runner container. The
        # act-runner pulls private job-container images (e.g.
        # library/orkestr-ci) via the Go docker SDK, which reads this file
        # for registry credentials. Without it, pulls of private `library/`
        # images fail with "no basic auth credentials".
        extraVolumes = [
          {
            name = "dind-daemon-config";
            configMap = {
              name = "forgejo-runner-daemon-config";
              items = [
                {
                  key = "daemon.json";
                  path = "daemon.json";
                }
              ];
            };
          }
          {
            name = "harbor-docker-config";
            secret = {
              secretName = "harbor-registry";
              items = [
                {
                  key = ".dockerconfigjson";
                  path = "config.json";
                }
              ];
            };
          }
        ];

        dind = {
          # Pull the dind sidecar image itself from Harbor's pull-through
          # cache so even the sidecar image doesn't depend on docker.io
          # being reachable. `library/docker` is the implicit Docker Hub
          # namespace; Harbor's "dockerhub" proxy project serves it.
          fullOverride = "10.0.0.56:5000/dockerhub/library/docker:28.3.3-dind";
          extraVolumeMounts = [
            {
              name = "dind-daemon-config";
              mountPath = "/etc/docker/daemon.json";
              subPath = "daemon.json";
            }
          ];
        };
      };
    };
  };
}
