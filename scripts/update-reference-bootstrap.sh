#!/usr/bin/env bash
# Update the reference bootstrap manifest for CI diff checking.
#
# Usage:
#   ./scripts/update-reference-bootstrap.sh
#
# This builds the bootstrap output from the current flake and copies it
# to docs/reference-bootstrap.yaml. Commit the result so CI can diff
# future changes against it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "Building bootstrap manifests..."
SYSTEM="$(nix eval --impure --raw --expr builtins.currentSystem)"
nix build ".#bootstrap.${SYSTEM}"

echo "Updating docs/reference-bootstrap.yaml..."
mkdir -p docs
cp result/bootstrap.yaml docs/reference-bootstrap.yaml

echo "✓ Reference bootstrap updated at docs/reference-bootstrap.yaml"
echo "  Commit it with: git add docs/reference-bootstrap.yaml && git commit -m 'chore(docs): update reference bootstrap'"
