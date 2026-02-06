{ config, lib, ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/${config.networking.hostName}.yaml;
    validateSopsFiles = true;
    age = {
      keyFile = "/etc/sops/age/keys.txt";
      generateKey = false;
    };
    secrets = { };
  };
}
