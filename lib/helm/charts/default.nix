{ helmLib }:

let
  argocd = import ./argocd.nix { inherit helmLib; };
  prometheus = import ./prometheus.nix { inherit helmLib; };
  ingress = import ./ingress.nix { inherit helmLib; };
  gitea = import ./gitea.nix { inherit helmLib; };
  clickhouse = import ./clickhouse.nix { inherit helmLib; };
  grafana = import ./grafana.nix { inherit helmLib; };
  cloudnative-pg = import ./cloudnative-pg.nix { inherit helmLib; };
  verdaccio = import ./verdaccio.nix { inherit helmLib; };
  infisical = import ./infisical.nix { inherit helmLib; };
  longhorn = import ./longhorn.nix { inherit helmLib; };
in
{
  # Re-export all charts
  inherit (argocd) argocd;
  inherit (prometheus) prometheus;
  inherit (ingress) ingress-nginx cert-manager;
  inherit (gitea) gitea;
  inherit (clickhouse) clickhouse clickhouse-operator;
  inherit (grafana) grafana loki tempo;
  inherit (cloudnative-pg) cloudnative-pg;
  inherit (verdaccio) verdaccio;
  inherit (infisical) infisical;
  inherit (longhorn) longhorn;

  # Convenience function to get all charts
  all = {
    inherit (argocd) argocd;
    inherit (prometheus) prometheus;
    inherit (ingress) ingress-nginx cert-manager;
    inherit (gitea) gitea;
    inherit (clickhouse) clickhouse clickhouse-operator;
    inherit (grafana) grafana loki tempo;
    inherit (cloudnative-pg) cloudnative-pg;
    inherit (verdaccio) verdaccio;
    inherit (infisical) infisical;
    inherit (longhorn) longhorn;
  };
}
