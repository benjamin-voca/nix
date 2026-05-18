#!/usr/bin/env bash
set -euo pipefail

echo "Building backbone-01..."
BACKBONE_PATH=$(nix build .#nixosConfigurations.backbone-01.config.system.build.toplevel --no-link --print-out-paths 2>/dev/null | tr -d '\n')
echo "backbone-01: $BACKBONE_PATH"

echo "Building frontline-01..."
FRONTLINE_PATH=$(nix build .#nixosConfigurations.frontline-01.config.system.build.toplevel --no-link --print-out-paths 2>/dev/null | tr -d '\n')
echo "frontline-01: $FRONTLINE_PATH"

echo "All builds successful."
