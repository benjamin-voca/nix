# SSH Access to Gitea via Cloudflare Tunnel

## Setup

The cloudflared tunnel is configured to route `gitea-ssh.quadtech.dev` to the Gitea SSH service.

### 1. Configure Cloudflare Tunnel Public Hostname

In Cloudflare Dashboard:
1. Go to **Zero Trust → Access → Tunnels**
2. Select your tunnel
3. Go to **Public Hostnames** tab
4. Click **Add a public hostname**:
   - **Subdomain**: `gitea-ssh`
   - **Domain**: `quadtech.dev`
   - **Type**: `TCP`
   - **URL**: `gitea-ssh.gitea.svc.cluster.local:22`
5. Click **Save hostname**

### 2. Configure SSH

Add to `~/.ssh/config`:

```ssh
Host gitea-ssh.quadtech.dev
  HostName gitea-ssh.quadtech.dev
  User git
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ProxyCommand cloudflared access tcp --hostname %h
```

### 3. Test

```bash
ssh git@gitea-ssh.quadtech.dev
```

## Alternative: Direct NodePort Access

If you prefer direct SSH without Cloudflare:

```bash
kubectl apply -f result/06-gitea-ssh-nodeport.yaml
```

Then SSH to: `backbone-01.quadtech.dev:32222`

## Troubleshooting

- **"websocket: bad handshake"**: Ensure Access Application is configured in Cloudflare Dashboard
- **"Permission denied"**: Add your SSH key to Gitea
- **"Connection refused"**: Verify cloudflared pod is running: `kubectl get pods -n cloudflared`
