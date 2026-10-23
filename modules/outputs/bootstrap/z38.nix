# Approved ZERO38 static site snapshot, including assets and nginx configuration.
{pkgs, lib}: {
  chartFiles = {};
  inlineFiles = {
    "29-z38.yaml" = builtins.readFile ../../../apps/z38/resources.json;
  };
  order = ["29-z38.yaml"];
}
