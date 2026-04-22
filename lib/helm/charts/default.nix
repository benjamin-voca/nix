{helmLib}: let
  argocd = import ./argocd.nix {inherit helmLib;};
  prometheus = import ./prometheus.nix {inherit helmLib;};
  ingress = import ./ingress.nix {inherit helmLib;};
  forgejo = import ./forgejo.nix {inherit helmLib;};
  forgejoActions = import ./forgejo-actions.nix {inherit helmLib;};
  clickhouse = import ./clickhouse.nix {inherit helmLib;};
  grafana = import ./grafana-simple.nix {inherit helmLib;};
  cloudnative-pg = import ./cloudnative-pg.nix {inherit helmLib;};
  verdaccio = import ./verdaccio.nix {inherit helmLib;};
  metallb = import ./metallb.nix {inherit helmLib;};
  harbor = import ./harbor.nix {inherit helmLib;};
  rookCeph = import ./rook-ceph.nix {inherit helmLib;};
  rookCephCluster = import ./rook-ceph-cluster.nix {inherit helmLib;};
in {
  # Re-export all charts
  inherit (argocd) argocd;
  inherit (prometheus) prometheus;
  inherit (ingress) ingress-nginx cert-manager;
  inherit (forgejo) forgejo;
  "forgejo-actions" = forgejoActions."forgejo-actions";
  inherit (clickhouse) clickhouse clickhouse-operator;
  inherit (grafana) grafana loki tempo;
  inherit (cloudnative-pg) cloudnative-pg;
  inherit (verdaccio) verdaccio;
  inherit (metallb) metallb;
  inherit (harbor) harbor;
  "rook-ceph" = rookCeph."rook-ceph";
  "rook-ceph-cluster" = rookCephCluster."rook-ceph-cluster";

  # Convenience function to get all charts
  all = {
    inherit (argocd) argocd;
    inherit (prometheus) prometheus;
    inherit (ingress) ingress-nginx cert-manager;
    inherit (forgejo) forgejo;
    "forgejo-actions" = forgejoActions."forgejo-actions";
    inherit (clickhouse) clickhouse clickhouse-operator;
    inherit (grafana) grafana loki tempo;
    inherit (cloudnative-pg) cloudnative-pg;
    inherit (verdaccio) verdaccio;
    inherit (metallb) metallb;
    inherit (harbor) harbor;
    "rook-ceph" = rookCeph."rook-ceph";
    "rook-ceph-cluster" = rookCephCluster."rook-ceph-cluster";
  };
}
