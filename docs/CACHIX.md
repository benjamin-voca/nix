# Cachix Integration

QuadNix includes declarative Cachix configuration for faster builds by using pre-built binary caches.

## Overview

Cachix is integrated at two levels:

1. **Flake level** (`flake.nix`) - Applies to `nix flake` commands
2. **System level** (`modules/profiles/cachix.nix`) - Applies to NixOS systems

This dual-level approach ensures that both flake operations and system rebuilds benefit from cached binaries.

## Configured Caches

### nixhelm
- **URL**: https://nixhelm.cachix.org
- **Purpose**: Pre-built Helm charts from nixhelm
- **Public Key**: `nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY=`

### nix-community
- **URL**: https://nix-community.cachix.org
- **Purpose**: Community-maintained packages and tools
- **Public Key**: `nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=`

### cache.nixos.org (default)
- **URL**: https://cache.nixos.org
- **Purpose**: Official NixOS binary cache
- **Public Key**: `cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=`

## Configuration Files

### Flake-level Configuration

File: `flake.nix`

```nix
{
  nixConfig = {
    extra-substituters = [
      "https://nixhelm.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
```

This configuration:
- Applies to all `nix flake` commands (build, update, show, etc.)
- No manual setup required
- Users automatically benefit from caches when using the flake

### System-level Configuration

File: `modules/profiles/cachix.nix`

```nix
{
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://nixhelm.cachix.org"
      "https://nix-community.cachix.org"
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
```

This configuration:
- Applies to all NixOS systems via `modules/profiles/base.nix`
- Persists across system rebuilds
- No imperative `cachix use` commands needed

## Benefits

### Speed Improvements

With Cachix enabled, expect significant speed improvements:

**Without Cachix:**
- Building nixhelm charts: 5-30 minutes
- Building complex derivations: Hours

**With Cachix:**
- Building nixhelm charts: Seconds (download only)
- Building complex derivations: Minutes (download only)

### Bandwidth Savings

Pre-built binaries are typically smaller than source downloads and much faster to fetch than building from source.

### No Manual Setup

Unlike the imperative approach:
```sh
# OLD WAY (not needed anymore)
cachix use nixhelm
cachix use nix-community
```

The declarative approach in this flake means:
- Caches are automatically configured
- Configuration is version-controlled
- Setup is reproducible across machines
- No user intervention required

## Verifying Cache Usage

### Check Active Substituters

On a NixOS system:
```sh
nix show-config | grep substituters
```

Expected output:
```
substituters = https://cache.nixos.org https://nixhelm.cachix.org https://nix-community.cachix.org
```

### Check Trusted Public Keys

```sh
nix show-config | grep trusted-public-keys
```

Expected output should include all three public keys.

### Test Cache Hit

Build a nixhelm chart and check if it's downloaded from cache:

```sh
nix build .#chartsDerivations.x86_64-linux.argoproj.argo-cd --print-build-logs
```

Look for:
- ✅ `copying path ... from 'https://nixhelm.cachix.org'` (cache hit)
- ❌ `building ...` (cache miss, building from source)

## Adding New Caches

To add additional Cachix caches:

### 1. Update Flake Configuration

Edit `flake.nix`:

```nix
nixConfig = {
  extra-substituters = [
    "https://nixhelm.cachix.org"
    "https://nix-community.cachix.org"
    "https://your-new-cache.cachix.org"  # Add new cache
  ];
  extra-trusted-public-keys = [
    "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "your-new-cache.cachix.org-1:YOUR_PUBLIC_KEY_HERE="  # Add key
  ];
};
```

### 2. Update System Configuration

Edit `modules/profiles/cachix.nix`:

```nix
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://nixhelm.cachix.org"
    "https://nix-community.cachix.org"
    "https://your-new-cache.cachix.org"  # Add new cache
  ];

  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "your-new-cache.cachix.org-1:YOUR_PUBLIC_KEY_HERE="  # Add key
  ];
};
```

### 3. Find Cache Public Keys

Visit the Cachix cache page to find the public key:
```
https://app.cachix.org/cache/<cache-name>
```

Or use the Cachix API:
```sh
curl https://<cache-name>.cachix.org/nix-cache-info
```

## Private Caches

For private Cachix caches (requires authentication):

### 1. Generate Auth Token

Visit: https://app.cachix.org/personal-auth-tokens

### 2. Add Token to NixOS Configuration

Using SOPS (recommended):

```nix
# secrets/cachix.yaml (encrypted with SOPS)
cachix-auth-token: "your-secret-token"
```

```nix
# modules/profiles/cachix.nix
{ config, ... }:
{
  sops.secrets."cachix-auth-token" = {
    sopsFile = ../secrets/cachix.yaml;
  };

  nix.settings = {
    netrc-file = config.sops.secrets."cachix-auth-token".path;
    # ... rest of configuration
  };
}
```

## Troubleshooting

### Cache Not Being Used

**Problem**: Builds are compiling from source instead of downloading.

**Solutions**:
1. Verify substituters are configured:
   ```sh
   nix show-config | grep substituters
   ```

2. Check public keys are trusted:
   ```sh
   nix show-config | grep trusted-public-keys
   ```

3. Rebuild system to apply changes:
   ```sh
   sudo nixos-rebuild switch --flake .#hostname
   ```

### Permission Denied

**Problem**: `error: cannot add path ... to the Nix store`

**Solution**: Ensure `trusted-public-keys` includes the cache's public key.

### Slow Downloads

**Problem**: Cache downloads are slow.

**Solutions**:
1. Check network connectivity to Cachix
2. Try a different Cachix mirror (if available)
3. Temporarily disable cache and build locally

## Security Considerations

### Trusting Public Keys

Only add public keys from trusted sources:
- ✅ Official Cachix caches (nixhelm, nix-community)
- ✅ Well-known community projects
- ❌ Unknown or untrusted sources

### Binary Trust

When you add a substituter and its public key:
- You're trusting that cache to provide correct binaries
- Nix verifies binaries against their hash
- Malicious cache could theoretically provide different binaries

### Mitigation

1. Only use well-known, reputable caches
2. Review cache configurations before adding
3. Use `trusted-substituters` to limit which users can use caches
4. For sensitive workloads, build from source

## Performance Monitoring

### Cache Hit Rate

Monitor how often builds use cache vs. building from source:

```sh
# Check recent downloads
nix path-info --all --json | jq '.[] | select(.url != null) | .url'
```

### Storage Usage

Cachix downloads are stored in `/nix/store`:

```sh
# Check store size
du -sh /nix/store

# Garbage collect unused paths
nix-collect-garbage -d
```

## Best Practices

1. **Keep configuration in version control** - Already done in this flake
2. **Use SOPS for private tokens** - Don't commit tokens to git
3. **Document cache purposes** - Add comments explaining why caches are needed
4. **Regularly update flake.lock** - Get latest cached binaries
5. **Monitor cache availability** - Some caches may go offline

## References

- [Cachix Documentation](https://docs.cachix.org/)
- [NixOS Manual: Binary Cache](https://nixos.org/manual/nix/stable/package-management/binary-cache.html)
- [nixhelm Cache](https://app.cachix.org/cache/nixhelm)
- [nix-community Cache](https://app.cachix.org/cache/nix-community)

## Summary

Cachix is now fully integrated declaratively in QuadNix:
- ✅ No manual `cachix use` commands needed
- ✅ Configuration is version-controlled
- ✅ Automatically applies to all systems
- ✅ Automatically applies to flake commands
- ✅ Faster builds for nixhelm charts
- ✅ Reproducible across machines
