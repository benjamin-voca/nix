{
  tunnelId,
  credentialsFile,
  metrics ? "0.0.0.0:2003",
  protocol ? "http2",
  ingress ? [
    {
      hostname = "mainssh.quadtech.dev";
      service = "ssh://localhost:22";
    }
    {
      hostname = "backbone-01.quadtech.dev";
      service = "ssh://localhost:22";
    }
    {
      hostname = "f1.quadtech.dev";
      service = "ssh://localhost:22";
    }
    {
      hostname = "forge-ssh.quadtech.dev";
      service = "tcp://127.0.0.1:32222";
    }
    {
      hostname = "forge.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "argocd.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "helpdesk.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "harbor.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "educourses-pd.com";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "www.educourses-pd.com";
      service = "http://127.0.0.1:30856";
    }
    {
      # Minecraft Java server on the MetalLB LoadBalancer VIP (reachable from
      # the host via kube-proxy). Vanilla/cracked clients cannot use a Cloudflare
      # Tunnel directly — connect via the LAN VIP 192.168.1.245 or over Tailscale.
      # This route only serves cloudflared-access users.
      hostname = "minecraft.quadtech.dev";
      service = "tcp://192.168.1.245:25565";
    }
    {
      hostname = "edukurs.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "batllavatourist.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "quadpacienti.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "openclaw.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "grafana.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "grafana.k8s.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "app.orkestr-os.com";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "api.orkestr-os.com";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "k8s.quadtech.dev";
      service = "tcp://127.0.0.1:6443";
    }
    {
      hostname = "chat.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      hostname = "*.quadtech.dev";
      service = "http://127.0.0.1:30856";
    }
    {
      service = "http_status:404";
    }
  ],
}: {
  tunnel = tunnelId;
  "credentials-file" = credentialsFile;
  protocol = protocol;
  metrics = metrics;
  "no-autoupdate" = true;
  ingress = ingress;
}
