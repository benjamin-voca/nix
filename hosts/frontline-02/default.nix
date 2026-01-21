{
  imports = [
    ./hardware.nix
    ../../roles/frontline.nix
  ];

  networking.hostName = "frontline-02";
}
