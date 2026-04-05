# SSH Access to Forgejo via Cloudflare Tunnel

## Setup

The cloudflared tunnel is configured to route `forge-ssh.quadtech.dev` to the Forgejo SSH service.

### 1. Configure Cloudflare Tunnel Public Hostname

In Cloudflare Dashboard:
1. Go to **Zero Trust → Access → Tunnels**
2. Select your tunnel
3. Go to **Public Hostnames** tab
4. Click **Add a public hostname**:
   - **Subdomain**: `forgejo-ssh`
   - **Domain**: `quadtech.dev`
   - **Type**: `TCP`
   - **URL**: `forgejo-ssh.forgejo.svc.cluster.local:22`
5. Click **Save hostname**

### 2. Configure SSH

Add to `~/.ssh/config`:

```ssh
Host forge-ssh.quadtech.dev
  HostName forge-ssh.quadtech.dev
  User git
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ProxyCommand cloudflared access tcp --hostname %h
```

### 3. Test

```bash
ssh git@forge-ssh.quadtech.dev
```

## Alternative: Direct NodePort Access

If you prefer direct SSH without Cloudflare:

```bash
kubectl apply -f result/06-forgejo-ssh-nodeport.yaml
```

Then SSH to: `backbone-01.quadtech.dev:32222`

## Troubleshooting

- **"websocket: bad handshake"**: Ensure Access Application is configured in Cloudflare Dashboard
- **"Permission denied"**: Add your SSH key to Forgejo
- **"Connection refused"**: Verify cloudflared pod is running: `kubectl get pods -n cloudflared`
