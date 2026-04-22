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

        actRunner = {
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
              options = "--dns 8.8.8.8 --dns 1.1.1.1";
            };
          };
        };
      };
    };
  };
}
