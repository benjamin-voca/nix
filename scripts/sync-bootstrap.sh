!# /usr/bin/env bash
SYSTEM="$(nix eval --impure --raw --expr builtins.currentSystem)" && \
nix build ".#bootstrap.${SYSTEM}" && \
kubectl apply --server-side --field-manager=quadnix-bootstrap --force-conflicts -f result/bootstrap.yaml
