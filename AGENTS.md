## QuadNix Agent Notes

- **Deploy (deploy-rs)**: `nix run github:serokell/deploy-rs -- .#backbone-01 --skip-checks`
- **Host definitions**: live in `modules/hosts/*.nix` using `config.quad.lib.mkClusterHost`
- **Core roles**: `modules/roles/backbone.nix`, `modules/roles/frontline.nix`
- **Profiles**: `modules/profiles/*` (base, server, docker, kubernetes)
- **Services**: `modules/services/*`
- **Shared options**: `modules/shared/*` (quad/k8s/gitea)
- **Outputs**: `modules/outputs/*` (nixosConfigurations, deploy, helm)

to run kubectl commands, prepend with `set -gx KUBECONFIG /etc/kubernetes/cluster-admin.kubeconfig` the commands that you will run inside of ssh host backbone01
