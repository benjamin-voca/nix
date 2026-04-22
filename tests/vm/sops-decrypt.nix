{
  inputs,
  pkgs,
  lib,
  ...
}: let
  encryptedSecret = pkgs.writeText "sops-vm-secret.yaml" ''
    string_secret: ENC[AES256_GCM,data:S1AtpCtrFGcq/QV5LvSi8zGd,iv:+kSRjmxR3aXXClZaZmIpUE7dQ9M5MyPUvCukkWewPxA=,tag:3fK0SAkbo1PV02pMnr/ncg==,type:str]
    sops:
        age:
            - recipient: age19we5280c0kz8qg5g8wlvpnh7m6s86r8h7at63zwhmv4ek7zkcgtsa2p6pa
              enc: |
                -----BEGIN AGE ENCRYPTED FILE-----
                YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBoVGkzczRLMEVLbDUxL2hp
                VW1vaXZxbGNHZVplS3A2VGoxVTZTeXFJa3hvCjJjYVdBaUE4OEFzNzNQMDdLbEh3
                MDdSNGx0V1BISTAxdjFjYm5RTlM3b1UKLS0tIEFNcG9TWVZtOXhHeGEzM2o2L25p
                WXBKTlBnbS9peHlGQTd5WEhOWEoyTm8KT39FJlcka1iDFWUlRjI2LNX/8uHSGZC+
                IK/c1nsGl1gC49G+Gsq6s2FO7TO82eO/Qbe0cD4w8zMMMlrJVILzLQ==
                -----END AGE ENCRYPTED FILE-----
        lastmodified: "2026-04-06T10:55:43Z"
        mac: ENC[AES256_GCM,data:hdcyPyfAaYmO1z0kwK1QyD+tTGu+vWMrGWxG3N73F/uT4nhU0CdYKtz48w28ue2aG4jq67TxhMaAzrkVpAS6hf49AknVJTAMFHCU0c7z923+bk8f4m6jCdsj4E+uu4n1TZSSDHtkBTzJcZBG8Fg1FPauz1TGGqzbE6uf1wWubok=,iv:BKY7Ck8CyDhvrWYEwecp5RZwLXrgbmJY4joWhL29+Cs=,tag:4wvVm5vSFOaPCvyXQXgq0g==,type:str]
        unencrypted_suffix: _unencrypted
        version: 3.11.0
  '';

  ageKey = pkgs.writeText "sops-vm-age-key.txt" ''
    # created: 2026-04-06T12:55:43+02:00
    # public key: age19we5280c0kz8qg5g8wlvpnh7m6s86r8h7at63zwhmv4ek7zkcgtsa2p6pa
    AGE-SECRET-KEY-10HHZS530MFRZT6PNTDFWLMGAPRXX34GTFA2AQN0PQME4PDP3R0WSQFYNJC
  '';
in
  pkgs.testers.nixosTest {
    name = "quadnix-vm-sops-decrypt";

    nodes.machine = {...}: {
      imports = [
        inputs.sops-nix.nixosModules.sops
        ../../modules/profiles/base.nix
        ../../modules/profiles/sops.nix
      ];

      networking.hostName = "sops-vm";

      sops = {
        defaultSopsFile = lib.mkForce encryptedSecret;
        age.keyFile = lib.mkForce "/run/sops-age/keys.txt";
        validateSopsFiles = lib.mkForce false;
        secrets.test-value = {
          key = "string_secret";
          owner = "root";
          group = "root";
          mode = "0400";
        };
      };

      boot.initrd.postDeviceCommands = ''
        mkdir -p /run/sops-age
        cp ${ageKey} /run/sops-age/keys.txt
        chmod 600 /run/sops-age/keys.txt
      '';
    };

    testScript = ''
      start_all()

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("sops-install-secrets.service")
      machine.succeed("test -f /run/secrets/test-value")
      machine.succeed("grep -q '^super-secret-value$' /run/secrets/test-value")
    '';
  }
