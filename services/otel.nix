{ config, pkgs, ... }:

{
  services.otelcol = {
    enable = true;
  };
}
