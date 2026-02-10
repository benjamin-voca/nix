# SSH Access to Gitea

## Direct SSH Access via NodePort (Port 32222)

The bootstrap creates a NodePort service exposing SSH on **port 32222** on the node's IP (Kubernetes NodePort range is 30000-32767).

### Router Configuration

You need to configure your router to forward port 32222 to your node's IP:
- **External Port**: 32222
- **Internal IP**: 192.168.1.14 (or your node's IP)
- **Internal Port**: 32222

### SSH Config

Add to `~/.ssh/config`:

```ssh
Host gitea-ssh.quadtech.dev
  HostName gitea-ssh.quadtech.dev
  User git
  Port 32222
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

### Test

```bash
ssh git@gitea-ssh.quadtech.dev
```

### Apply

```bash
nix build .#bootstrap.x86_64-linux
kubectl apply -f result/06-gitea-ssh-nodeport.yaml
kubectl get svc -n gitea gitea-ssh-nodeport  # Verify nodePort: 32222
```

## Alternative: Via Cloudflare Tunnel (Requires Access)

If you want SSH through Cloudflare Tunnel with Zero Trust security:

### 1. Create Access Application

In Cloudflare Dashboard:
1. **Zero Trust → Access → Applications**
2. **Add an application** → **Self-hosted**
3. Configure:
   - Application name: `gitea-ssh`
   - Subdomain: `gitea-ssh`
   - Domain: `quadtech.dev`
4. Add policy: Allow your email
5. Save

### 2. Create Service Token

1. **Zero Trust → Access → Service Tokens**
2. **Create Service Token**
3. Name: `gitea-ssh-token`
4. Copy Client ID and Secret

### 3. SSH Config

```ssh
Host gitea-ssh.quadtech.dev
  HostName gitea-ssh.quadtech.dev
  User git
  Port 32222
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ProxyCommand cloudflared access tcp --hostname %h --id CLIENT_ID --secret CLIENT_SECRET
```

## Troubleshooting

- **Connection refused**: Check router port forwarding is configured
- **Connection timeout**: Verify firewall rules allow port 32222
- **Authentication failed**: Verify SSH key is added to Gitea
- **Check service**: `kubectl get svc -n gitea gitea-ssh-nodeport`
- **Test locally**: `nc -zv 192.168.1.14 32222` (from backbone-01)
