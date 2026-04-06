{ config, lib, inputs, ... }:

let
  systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  forAllSystems = lib.genAttrs systems;
  repoSrc = builtins.path {
    path = ../../.;
    name = "quadnix-source";
  };

  nixModuleTests = {
    quad-mk-cluster-host = "tests/nix/quad/mk-cluster-host.test.nix";
    quad-hosts-output = "tests/nix/quad/hosts-output.test.nix";
    shared-common = "tests/nix/shared/common.test.nix";
    k8s-control-plane = "tests/nix/kubernetes/control-plane.test.nix";
    k8s-worker = "tests/nix/kubernetes/worker.test.nix";
  };

  mkNixExpressionCheck = pkgs: system: name: relativeTestPath:
    pkgs.runCommand "test-${name}"
      {
        nativeBuildInputs = [ pkgs.nix ];
      }
      ''
        nix-instantiate --eval --strict "${repoSrc}/${relativeTestPath}" \
          --arg pkgs 'import ${inputs.nixpkgs} { system = "${system}"; }' \
          >/dev/null
        touch "$out"
      '';
in
{
  config.flake.checks = forAllSystems (
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};

      unitChecks = lib.mapAttrs (
        name: testPath: mkNixExpressionCheck pkgs system name testPath
      ) nixModuleTests;
    in
    unitChecks
    // {
      manifests-kubeconform = pkgs.runCommand "validate-bootstrap-manifests"
        {
          nativeBuildInputs = [ pkgs.kubeconform ];
        }
        ''
          kubeconform \
            -summary \
            -strict \
            -ignore-missing-schemas \
            -kubernetes-version 1.29.0 \
            ${config.flake.bootstrap.${system}}/bootstrap.yaml
          touch "$out"
        '';

      manifests-policy = pkgs.runCommand "policy-check-bootstrap"
        {
          nativeBuildInputs = [ pkgs.conftest ];
        }
        ''
          conftest test --policy ${../../tests/policy} ${config.flake.bootstrap.${system}}/bootstrap.yaml
          touch "$out"
        '';
    }
    // lib.optionalAttrs (system == "x86_64-linux") {
      vm-backbone-control-plane = import ../../tests/vm/backbone-control-plane.nix {
        inherit inputs lib pkgs;
      };

      vm-frontline-worker = import ../../tests/vm/frontline-worker.nix {
        inherit inputs lib pkgs;
      };

      vm-sops-decrypt = import ../../tests/vm/sops-decrypt.nix {
        inherit inputs lib pkgs;
      };
    }
  );

  config.flake.formatter = forAllSystems (system: inputs.nixpkgs.legacyPackages.${system}.alejandra);
}
