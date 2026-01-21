{ config, pkgs, ... }:

{
  services.opentelemetry = {
    enable = true;
  };
}
