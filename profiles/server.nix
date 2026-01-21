{
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "fs.inotify.max_user_watches" = 524288;
  };

  services.journald.extraConfig = ''
    SystemMaxUse=2G
  '';

  security.sudo.wheelNeedsPassword = false;
}
