# Secrets Directory

This directory contains **encrypted** secrets managed by [SOPS](https://github.com/getsops/sops).

## What's Safe to Commit

✅ **Encrypted `.yaml` files** - These are encrypted with age and safe to commit to git
✅ **This README.md**
❌ **`.yaml.template` files** - These are unencrypted templates, never commit
❌ **`.json` files** - These might contain credentials, never commit
❌ **`.txt` files** - These might contain private keys, never commit

## Files

- `backbone-01.yaml.template` - Template for backbone-01 secrets (unencrypted)
- `backbone-01.yaml` - Encrypted secrets for backbone-01 (safe to commit after encryption)
- `backbone-02.yaml` - Encrypted secrets for backbone-02 (if created)
- `global.yaml` - Encrypted secrets shared across all hosts (if created)

## How to Use

See [SOPS-SETUP.md](../docs/SOPS-SETUP.md) for complete instructions.

### Quick Start

1. **Set up age keys on backbone-01:**
   ```bash
   sudo mkdir -p /etc/sops/age
   sudo age-keygen -o /etc/sops/age/keys.txt
   sudo cat /etc/sops/age/keys.txt | grep "public key:"
   ```

2. **Update `.sops.yaml` with your public key**

3. **Encrypt the template:**
   ```bash
   # Fill in the template first with your actual credentials
   cp secrets/backbone-01.yaml.template secrets/backbone-01.yaml.tmp
   # Edit with actual values
   vim secrets/backbone-01.yaml.tmp
   # Encrypt
   nix-shell -p sops --run "sops -e secrets/backbone-01.yaml.tmp > secrets/backbone-01.yaml"
   # Delete temporary file
   rm secrets/backbone-01.yaml.tmp
   ```

4. **Or edit directly (auto-encrypts):**
   ```bash
   nix-shell -p sops --run "sops secrets/backbone-01.yaml"
   ```

5. **Commit the encrypted file:**
   ```bash
   git add secrets/backbone-01.yaml
   git commit -m "Add encrypted backbone-01 secrets"
   git push
   ```

## Editing Secrets

```bash
# Edit encrypted file (must have access to private key)
nix-shell -p sops --run "sops secrets/backbone-01.yaml"

# View decrypted content without editing
nix-shell -p sops --run "sops -d secrets/backbone-01.yaml"
```

## Security

- **Private keys** are stored in `/etc/sops/age/keys.txt` on each host
- **Never commit** private keys to git
- **Encrypted files** in this directory are safe to commit
- **Backup** your private keys securely (encrypted USB, password manager, etc.)
