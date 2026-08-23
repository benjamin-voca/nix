# SSH Access to Forgejo via Cloudflare Tunnel

## Setup

The cloudflared tunnel is configured to route `forge-ssh.voltrum.co` to the Forgejo SSH service.

### 1. Configure Cloudflare Tunnel Public Hostname

In Cloudflare Dashboard:
1. Go to **Zero Trust → Access → Tunnels**
2. Select your tunnel
3. Go to **Public Hostnames** tab
4. Click **Add a public hostname**:
   - **Subdomain**: `forge-ssh`
   - **Domain**: `voltrum.co`
   - **Type**: `TCP`
   - **URL**: `127.0.0.1:32222`
5. Click **Save hostname**

### 2. Configure SSH

Add to `~/.ssh/config`:

```ssh
Host forge-ssh.voltrum.co
  HostName forge-ssh.voltrum.co
  User git
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ProxyCommand cloudflared access tcp --hostname %h
```

### 3. Test

```bash
ssh git@forge-ssh.voltrum.co
```

## Alternative: Direct NodePort Access

If you prefer direct SSH without Cloudflare:

```bash
kubectl -n forgejo get svc forgejo-ssh
```

Then SSH to: `backbone-01.voltrum.co:32222`

## Troubleshooting

- **"websocket: bad handshake"**: Ensure Access Application is configured in Cloudflare Dashboard
- **"Permission denied"**: Add your SSH key to Forgejo
- **"Connection refused"**: Verify cloudflared pod is running: `kubectl get pods -n cloudflared`
