{ pkgs }:

{
  # Merge multiple Helm values files
  mergeValues = values:
    pkgs.lib.foldl' pkgs.lib.recursiveUpdate {} values;

  # Convert Nix attribute set to YAML for Helm values
  toYAML = values:
    pkgs.writeText "values.yaml" (builtins.toJSON values);

  # Helper to create a namespace manifest
  mkNamespace = name: {
    apiVersion = "v1";
    kind = "Namespace";
    metadata = {
      inherit name;
    };
  };

  # Helper to create a values overlay for common settings
  mkCommonValues = { namespace, replicas ? 1, resources ? {} }: {
    inherit namespace replicas;
    resources = pkgs.lib.recursiveUpdate {
      requests = {
        cpu = "100m";
        memory = "128Mi";
      };
      limits = {
        cpu = "1000m";
        memory = "512Mi";
      };
    } resources;
  };

  # Create an ArgoCD Application manifest for GitOps
  mkArgoApplication = { name, namespace, repoURL, path, targetRevision ? "HEAD" }: {
    apiVersion = "argoproj.io/v1alpha1";
    kind = "Application";
    metadata = {
      inherit name namespace;
    };
    spec = {
      project = "default";
      source = {
        inherit repoURL path targetRevision;
      };
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

  # Validate that required values are present
  validateValues = requiredKeys: values:
    let
      missingKeys = pkgs.lib.filter (key: !(builtins.hasAttr key values)) requiredKeys;
    in
      if missingKeys == []
      then values
      else throw "Missing required values: ${builtins.toString missingKeys}";
}
