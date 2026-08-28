# Local ingress for the backbone Cloudflare Tunnel.
#
# IMPORTANT: this tunnel is remotely configured. On connect, cloudflared
# pulls ingress from the Cloudflare API and overwrites this file's rules.
# After changing hostnames here, also PUT
#   /accounts/{id}/cfd_tunnel/{tunnelId}/configurations
# (the cert.pem Argo Tunnel token can auth that API). DNS CNAMEs live in
# the voltrum.co zone, NOT via `cloudflared tunnel route dns` (that CLI is
# bound to the quadtech.dev zone in cert.pem).
{
  tunnelId,
  credentialsFile,
  metrics ? "0.0.0.0:2003",
  protocol ? "http2",
  ingress ? null,
}: let
  d = import ./domain.nix;
  httpNode = "http://127.0.0.1:30856";
  httpHost = name: {
    hostname = d.host name;
    service = httpNode;
  };
  defaultIngress = [
    {
      hostname = d.host "mainssh";
      service = "ssh://localhost:22";
    }
    {
      hostname = d.host "backbone-01";
      service = "ssh://localhost:22";
    }
    {
      hostname = d.host "f1";
      service = "ssh://localhost:22";
    }
    {
      hostname = d.host "forge-ssh";
      service = "tcp://127.0.0.1:32222";
    }
    (httpHost "forge")
    (httpHost "argocd")
    (httpHost "harbor")
    {
      hostname = "educourses-pd.com";
      service = httpNode;
    }
    {
      hostname = "www.educourses-pd.com";
      service = httpNode;
    }
    (httpHost "edukurs")
    (httpHost "batllavatourist")
    (httpHost "openclaw")
    (httpHost "grafana")
    {
      # Minecraft Java server on the MetalLB LoadBalancer VIP (reachable from
      # the host via kube-proxy). Vanilla/cracked clients cannot use a Cloudflare
      # Tunnel directly — connect via the LAN VIP 192.168.1.245 or over Tailscale.
      # This route only serves cloudflared-access users.
      hostname = d.host "minecraft";
      service = "tcp://192.168.1.245:25565";
    }
    (httpHost "edukurs")
    (httpHost "batllavatourist")
    (httpHost "openclaw")
    (httpHost "grafana")
    {
      hostname = d.host "n8n";
      service = "https://127.0.0.1:31797";
      "originRequest" = {
        "noTLSVerify" = true;
      };
    }
    {
      hostname = d.host "huly";
      service = "https://127.0.0.1:31797";
      "originRequest" = {
        "noTLSVerify" = true;
      };
    }
    {
      hostname = "app.orkestr-os.com";
      service = httpNode;
    }
    {
      hostname = "api.orkestr-os.com";
      service = httpNode;
    }
    {
      hostname = d.host "k8s";
      service = "tcp://127.0.0.1:6443";
    }
    {
      hostname = d.host "*";
      # TLS origin hop so nginx reports X-Forwarded-Proto: https — required
      # for HyperDX's Secure session cookies (express-session withholds
      # Set-Cookie when the app sees a plain-http hop). cert is the
      # ingress-nginx default self-signed, hence noTLSVerify.
      service = "https://127.0.0.1:31797";
      "originRequest" = {
        "noTLSVerify" = true;
      };
    }
    {
      service = "http_status:404";
    }
  ];
in {
  tunnel = tunnelId;
  "credentials-file" = credentialsFile;
  protocol = protocol;
  metrics = metrics;
  "no-autoupdate" = true;
  ingress =
    if ingress == null
    then defaultIngress
    else ingress;
}
