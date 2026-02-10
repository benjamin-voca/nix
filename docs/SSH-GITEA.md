# SSH Access to Gitea

## Option 1: Direct SSH via LoadBalancer (Recommended)

The bootstrap creates a LoadBalancer service exposing SSH on port 2222.

### Configure DNS

Ensure `gitea-ssh.quadtech.dev` points to your node's external IP. The LoadBalancer service has external-dns annotation.

### SSH Config

Add to `~/.ssh/config`:

```ssh
Host gitea-ssh.quadtech.dev
  HostName gitea-ssh.quadtech.dev
  User git
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

### Test

```bash
ssh git@gitea-ssh.quadtech.dev
```

## Option 2: Via Cloudflare Tunnel (Requires Access)

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
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ProxyCommand cloudflared access tcp --hostname %h --id CLIENT_ID --secret CLIENT_SECRET
```

## Troubleshooting

- **Connection refused**: Check LoadBalancer has external IP: `kubectl get svc -n gitea gitea-ssh-lb`
- **DNS not resolving**: Wait for external-dns or manually create A record
- **Authentication failed**: Verify SSH key is added to Gitea
