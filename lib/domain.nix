# Canonical public domain for QuadNix services.
#
# All tunnel hostnames, Ingress hosts, and app ROOT_URLs should go through
# these helpers so a future rename is one line.
rec {
  domain = "voltrum.co";

  host = name: "${name}.${domain}";
  url = name: "https://${host name}";
  email = local: "${local}@${domain}";
}
