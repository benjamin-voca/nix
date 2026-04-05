{ helmLib }:

let
  compatChartSource = "https://dl." + "gitea" + ".com/charts";
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
      giteaRootURL = "https://forge.quadtech.dev";
      existingSecret = "forgejo-runner-token";
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
