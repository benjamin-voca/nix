{ config, pkgs, ... }:

{
  services.buildkite = {
    enable = true;
  };
}
