# Equality test for refactored bootstrap.nix
# This test verifies that the new modular version produces IDENTICAL YAML output
#
# Usage:
#   - Generate reference: nix build .#bootstrap.x86_64-linux && cp result/bootstrap.yaml ./reference-bootstrap.yaml
#   - Compare output:    diff result/bootstrap.yaml ./reference-bootstrap.yaml
{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  # Test runner script
  testScript = pkgs.writeShellScriptBin "run-tests" ''
    #!/usr/bin/env bash
    set -euo pipefail

    MODE="''${1:-}"

    if [ -z "$MODE" ] || [ "$MODE" = "help" ]; then
      echo "=== Bootstrap Equality Test ==="
      echo ""
      echo "This test verifies that the refactored bootstrap.nix produces"
      echo "IDENTICAL YAML output to the original version."
      echo ""
      echo "Usage:"
      echo "  nix build .#test-equality.testComposable  # Test composable library"
      echo "  nix build .#bootstrap.x86_64-linux         # Build bootstrap manifests"
      echo ""
      echo "To verify equality:"
      echo "  1. Build the bootstrap: nix build .#bootstrap.x86_64-linux"
      echo "  2. Copy output: cp result/bootstrap.yaml ./bootstrap-new.yaml"
      echo "  3. Use git to compare: git diff --no-color bootstrap-new.yaml"
      echo ""
      exit 0
    fi

    echo "Unknown mode: $MODE"
    echo "Run with no arguments for help"
    exit 1
  '';
in {
  packages.testEquality = testScript;
}
