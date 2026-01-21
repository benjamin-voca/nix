{
  imports = [
    ./hardware.nix
    ../../roles/backbone.nix
  ];

  networking.hostName = "backbone-02";
}
