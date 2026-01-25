{ config, lib, ... }:

{
  # SOPS Configuration
  # This profile sets up sops-nix for managing secrets
  
  sops = {
    # Default SOPS file for this host
    defaultSopsFile = ../secrets/${config.networking.hostName}.yaml;
    
    # Validate secrets at build time (recommended)
    validateSopsFiles = true;
    
    # Age key file location (standard path)
    age = {
      keyFile = "/etc/sops/age/keys.txt";
      
      # Generate a key if it doesn't exist (useful for first boot)
      # Set to false in production for security
      generateKey = false;
      
      # SSH host keys can also be used (fallback)
      # sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
    
    # Secrets definition
    # Individual hosts override this in their configuration
    secrets = {
      # Example structure - actual secrets defined per-host
      # cloudflared-credentials = {
      #   sopsFile = ../secrets/${config.networking.hostName}.yaml;
      #   path = "/run/secrets/cloudflared-credentials.json";
      #   owner = "root";
      #   group = "root";
      #   mode = "0400";
      # };
    };
  };
}
