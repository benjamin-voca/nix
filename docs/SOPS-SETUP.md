# SOPS Setup Guide for QuadNix

## Step 1: Generate Age Keys on Each Host

Run these commands **on each host** (backbone-01, backbone-02, etc.):

```bash
# Install age if not already installed
nix-shell -p age --run "age-keygen -o /etc/sops/age/keys.txt"

# Or if age is already installed:
sudo mkdir -p /etc/sops/age
sudo age-keygen -o /etc/sops/age/keys.txt

# Set proper permissions
sudo chmod 600 /etc/sops/age/keys.txt
sudo chown root:root /etc/sops/age/keys.txt

# View the PUBLIC key (you'll need this for .sops.yaml)
sudo cat /etc/sops/age/keys.txt | grep "public key:"
```

**Save the public keys!** You'll need them for the next step.

Example output:
```
# public key: age1abc123...xyz789
```

## Step 2: Get Your Cloudflare Credentials File

On backbone-01, copy your existing credentials:

```bash
# View the credentials file
cat /home/klajd/.cloudflared/9832df66-f04a-40ea-b004-f6f9b100eb14.json

# Copy the entire JSON content - you'll encrypt this with SOPS
```

## Step 3: Update .sops.yaml with Your Public Keys

After you have your public keys from Step 1, I'll update the `.sops.yaml` file.

**Please provide:**
1. The public key from backbone-01: `age1...`
2. The public key from backbone-02 (if you have it): `age1...`
3. Your personal workstation public key (optional, for editing secrets): `age1...`

## Step 4: Encrypt the Cloudflare Credentials

Once `.sops.yaml` is configured, run:

```bash
# Create the secrets directory
mkdir -p secrets

# Create a new encrypted file for backbone-01 secrets
nix-shell -p sops --run "sops secrets/backbone-01.yaml"
```

This will open an editor. Add your Cloudflare credentials:

```yaml
cloudflared:
  tunnel-id: "9832df66-f04a-40ea-b004-f6f9b100eb14"
  credentials-json: |
    {
      "AccountTag": "your-account-tag",
      "TunnelSecret": "your-tunnel-secret",
      "TunnelID": "9832df66-f04a-40ea-b004-f6f9b100eb14"
    }
```

Save and exit. The file will be automatically encrypted!

## Step 5: Verify Encryption

```bash
# View the encrypted file
cat secrets/backbone-01.yaml
# Should show encrypted content with sops metadata

# Decrypt to verify (must be on backbone-01 or have the private key)
nix-shell -p sops --run "sops -d secrets/backbone-01.yaml"
```

## Step 6: Commit to Git

```bash
git add .sops.yaml secrets/
git commit -m "Add SOPS encrypted secrets"
git push
```

The encrypted secrets are now safely in git!

## What Happens During Boot

When backbone-01 boots:
1. sops-nix reads `/etc/sops/age/keys.txt` (private key)
2. Decrypts `secrets/backbone-01.yaml` using the private key
3. Creates `/run/secrets/cloudflared-credentials.json` with proper permissions
4. Cloudflared service reads from `/run/secrets/cloudflared-credentials.json`

## Security Notes

- ✅ **Private keys** (`/etc/sops/age/keys.txt`) stay on each host, never in git
- ✅ **Encrypted secrets** (`secrets/*.yaml`) are safe to commit to git
- ✅ **Public keys** (in `.sops.yaml`) are safe to commit to git
- ✅ Only hosts with the private key can decrypt their secrets
- ⚠️ **Backup** `/etc/sops/age/keys.txt` securely (encrypted USB, password manager, etc.)

## Rotating Secrets

To update the Cloudflare credentials:

```bash
# Edit the encrypted file
nix-shell -p sops --run "sops secrets/backbone-01.yaml"

# Commit the changes
git add secrets/backbone-01.yaml
git commit -m "Update Cloudflare credentials"
git push

# Rebuild on the host
sudo nixos-rebuild switch --flake .#backbone-01
```

## Next Steps

After completing these steps, return to the main setup and I'll configure the NixOS modules to use these secrets!
