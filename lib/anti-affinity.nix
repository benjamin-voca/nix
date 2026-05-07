appName: {
  podAntiAffinity = {
    preferredDuringSchedulingIgnoredDuringExecution = [
      {
        weight = 100;
        podAffinityTerm = {
          labelSelector = {
            matchExpressions = [
              {
                key = "app";
                operator = "In";
                values = [appName];
              }
            ];
          };
          topologyKey = "kubernetes.io/hostname";
        };
      }
    ];
  };
}
