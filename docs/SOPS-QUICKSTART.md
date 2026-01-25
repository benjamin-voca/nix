# SOPS Quick Start for QuadNix

This guide will walk you through setting up SOPS to securely store your Cloudflare Tunnel credentials in git.

## What You'll Do

1. Generate an age key pair on backbone-01
2. Update `.sops.yaml` with your public key
3. Encrypt your Cloudflare credentials
4. Commit encrypted secrets to git
5. Deploy with `nixos-rebuild`

## Step 1: Generate Age Key on backbone-01

SSH into backbone-01 and run:

```bash
# Install age and generate a key
sudo mkdir -p /etc/sops/age
sudo nix-shell -p age --run "age-keygen -o /etc/sops/age/keys.txt"

# Set proper permissions
sudo chmod 600 /etc/sops/age/keys.txt
sudo chown root:root /etc/sops/age/keys.txt

# View your PUBLIC key (you'll need this!)
sudo cat /etc/sops/age/keys.txt | grep "public key:"
```

**Save the output!** It will look like:
```
# public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Copy that `age1...` string - you'll need it in the next step.

## Step 2: Update .sops.yaml

On your local machine, edit `.sops.yaml` and replace the placeholder:

```yaml
keys:
  # Backbone hosts
  - &backbone-01 age1YOUR_ACTUAL_PUBLIC_KEY_HERE  # ← Replace this
  - &backbone-02 age1REPLACE_WITH_BACKBONE_02_PUBLIC_KEY
```

Example:
```yaml
keys:
  - &backbone-01 age1wfv7kzrmhmd5234example7nh2k3j8qy9z5x4c8v2b3n9m8k7j6h5g4f
  - &backbone-02 age1REPLACE_WITH_BACKBONE_02_PUBLIC_KEY  # Leave as is if you don't have it yet
```

## Step 3: Get Your Cloudflare Credentials

On backbone-01, view your current credentials file:

```bash
cat /home/klajd/.cloudflared/9832df66-f04a-40ea-b004-f6f9b100eb14.json
```

Copy the entire JSON output. It should look like:

```json
{
  "AccountTag": "abc123...",
  "TunnelSecret": "xyz789...",
  "TunnelID": "9832df66-f04a-40ea-b004-f6f9b100eb14"
}
```

## Step 4: Create and Encrypt the Secrets File

On your **local machine** (or on backbone-01 if you prefer):

```bash
# Enter nix shell with sops
nix-shell -p sops

# Create and edit the encrypted secrets file
sops secrets/backbone-01.yaml
```

This will open your editor. Add the following content:

```yaml
cloudflared:
  tunnel-id: "9832df66-f04a-40ea-b004-f6f9b100eb14"
  credentials-json: |
    {
      "AccountTag": "paste-your-account-tag-here",
      "TunnelSecret": "paste-your-tunnel-secret-here",
      "TunnelID": "9832df66-f04a-40ea-b004-f6f9b100eb14"
    }
```

**Important:** The YAML structure must have:
- `cloudflared` → `credentials-json` (note the underscore!)
- The JSON credentials as a multi-line string using `|`

**Save and exit.** SOPS will automatically encrypt the file!

## Step 5: Verify the Encryption

```bash
# View the encrypted file (should show encrypted content)
cat secrets/backbone-01.yaml

# You should see something like:
# cloudflared:
#   tunnel-id: ENC[AES256_GCM,data:abc123...,tag:xyz...]
#   credentials-json: ENC[AES256_GCM,data:def456...,tag:uvw...]
# sops:
#   ...metadata...
```

If you see plaintext instead of `ENC[...]`, something went wrong. Make sure:
- `.sops.yaml` has the correct public key
- You're editing `secrets/backbone-01.yaml` (not the `.template` file)

## Step 6: Test Decryption (on backbone-01)

Transfer the encrypted file to backbone-01 and test decryption:

```bash
# On backbone-01
cd /etc/nixos
git pull  # If you've already pushed, or copy the file manually

# Test decryption (you should see the plaintext)
nix-shell -p sops --run "sops -d secrets/backbone-01.yaml"
```

If this shows your plaintext credentials, encryption is working! ✅

## Step 7: Commit to Git

```bash
# On your local machine
git add .sops.yaml secrets/backbone-01.yaml
git commit -m "Add SOPS encrypted Cloudflare credentials"
git push
```

The encrypted file is now safely in git!

## Step 8: Deploy on backbone-01

```bash
# On backbone-01
cd /etc/nixos
git pull

# Rebuild NixOS with SOPS integration
sudo nixos-rebuild switch --flake .#backbone-01
```

If everything worked:
- ✅ SOPS will decrypt `secrets/backbone-01.yaml`
- ✅ Extract the `cloudflared.credentials-json` value
- ✅ Write it to `/run/secrets/cloudflared-credentials.json`
- ✅ cloudflared service will start using the decrypted credentials

## Step 9: Verify Everything Works

```bash
# Check if the secret was created
ls -la /run/secrets/cloudflared-credentials.json

# Check cloudflared service status
systemctl status cloudflared.service

# Test your tunnel
curl https://gitea.quadtech.dev
```

## Troubleshooting

### Error: "no decryption key found for your private key"

**Cause:** The public key in `.sops.yaml` doesn't match the private key in `/etc/sops/age/keys.txt`

**Fix:** 
1. Double-check the public key: `sudo cat /etc/sops/age/keys.txt | grep "public key:"`
2. Update `.sops.yaml` with the correct key
3. Re-encrypt the file: `sops --rotate secrets/backbone-01.yaml`

### Error: "failed to get the data key required to decrypt"

**Cause:** The file was encrypted with a different public key

**Fix:** Re-encrypt the file:
```bash
# Delete old encrypted file
rm secrets/backbone-01.yaml

# Create new encrypted file with correct key
sops secrets/backbone-01.yaml
# ... paste content and save
```

### Error: "age key not found: /etc/sops/age/keys.txt"

**Cause:** Age key file doesn't exist on the host

**Fix:** Generate the key (see Step 1)

### Cloudflared fails with "invalid credentials"

**Cause:** The credentials JSON might be malformed

**Fix:** Verify the structure:
```bash
# Decrypt and check the JSON
sops -d secrets/backbone-01.yaml | yq .cloudflared.credentials-json

# Should output valid JSON
```

## What Got Created

After successful setup:

- ✅ `/etc/sops/age/keys.txt` - Private key (on backbone-01, **NEVER in git**)
- ✅ `.sops.yaml` - SOPS configuration (**safe to commit**)
- ✅ `secrets/backbone-01.yaml` - Encrypted secrets (**safe to commit**)
- ✅ `/run/secrets/cloudflared-credentials.json` - Decrypted at runtime (auto-created)

## Next Steps

1. **Backup your private key!**
   ```bash
   # On backbone-01
   sudo cp /etc/sops/age/keys.txt ~/age-key-backup.txt
   # Store this securely (encrypted USB, password manager, etc.)
   ```

2. **Set up backbone-02** (repeat Steps 1-8 for backbone-02)

3. **Add more secrets** as needed:
   ```bash
   # Edit the encrypted file
   sops secrets/backbone-01.yaml
   
   # Add new secrets under different keys:
   # gitea:
   #   admin-password: "..."
   # grafana:
   #   admin-password: "..."
   ```

4. **Configure services to use SOPS secrets** in `roles/backbone.nix`:
   ```nix
   sops.secrets.gitea-admin-password = {
     sopsFile = ../secrets/${config.networking.hostName}.yaml;
   };
   
   services.gitea = {
     database.passwordFile = config.sops.secrets.gitea-admin-password.path;
   };
   ```

## Security Reminders

- ✅ Encrypted SOPS files are safe to commit to git
- ✅ Public keys in `.sops.yaml` are safe to commit
- ❌ **NEVER commit** `/etc/sops/age/keys.txt` (private key)
- ❌ **NEVER commit** unencrypted `.yaml.template` files
- 🔐 **Backup** your private key securely (you can't decrypt without it!)

## Reference

- [SOPS GitHub](https://github.com/getsops/sops)
- [sops-nix Documentation](https://github.com/Mic92/sops-nix)
- [Age Encryption Tool](https://age-encryption.org/)
- QuadNix SOPS docs: `docs/SOPS-SETUP.md`
