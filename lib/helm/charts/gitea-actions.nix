{ helmLib }:

{
  gitea-actions = helmLib.buildChart {
    name = "gitea-actions";
    chart = helmLib.kubelib.downloadHelmChart {
      repo = "https://dl.gitea.com/charts";
      chart = "actions";
      version = "0.0.3";
      chartHash = "sha256-7b9a041a8bbf9dac7098a12331802b6c71d1f158deeb0a5e2f5aa1e969c97ed0";
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
