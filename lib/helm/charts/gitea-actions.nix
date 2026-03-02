{ helmLib }:

{
  gitea-actions = helmLib.buildChart {
    name = "gitea-actions";
    chart = helmLib.kubelib.downloadHelmChart {
      repo = "https://dl.gitea.com/charts";
      chart = "actions";
      version = "0.0.3";
      chartHash = "sha256-e5oEGou/naxwmKEjMYArbHHR8Vje6wpeL1qh6WnJftA=";
    };
    namespace = "gitea";
    values = {
      giteaRootURL = "https://gitea.quadtech.dev";
      existingSecret = "gitea-runner-token";
      existingSecretKey = "token";

      statefulset = {
        replicas = 2;

        actRunner = {
          config = {
            runner = {
              extra = [
                "ubuntu-latest"
                "linux"
                "x86_64"
                "self-hosted"
              ];
            };
          };
        };
      };
    };
  };
}
