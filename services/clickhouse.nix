{ config, pkgs, ... }:

{
  services.clickhouse = {
    enable = true;
  };
}
