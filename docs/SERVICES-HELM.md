# Helm services on backbone-01

This repo builds Helm charts via nixhelm/nix-kube-generators. The flow below uses the
preconfigured charts in `lib/helm/charts/` and keeps Cloudflare Tunnel as the public edge.

## Architecture

- Cloudflare Tunnel routes `*.quadtech.dev` to ingress-nginx (ClusterIP)
- ingress-nginx routes to services via Ingress
- cert-manager is not required (Cloudflare terminates TLS)
- CloudNativePG provides Postgres for apps that need it

## Namespaces

Apply the namespaces first:

```sh
kubectl apply -f manifests/backbone/namespaces.yaml
```

## CloudNativePG

Install the operator:

```sh
nix build .#helmCharts.x86_64-linux.all.cloudnative-pg
helm upgrade --install cloudnative-pg ./result/*.tgz -n cnpg-system --create-namespace
```

Create the Postgres clusters and app secrets:

```sh
SOPS_AGE_KEY_FILE=~/.sops/age/keys.txt sops -d secrets/backbone-01.yaml \
  | rg -n "gitea-db-password|infisical-db-password|infisical-encryption-key|infisical-auth-secret"

gitea_db_password=$(SOPS_AGE_KEY_FILE=~/.sops/age/keys.txt sops -d secrets/backbone-01.yaml | rg -o "gitea-db-password: (.*)$" -r '$1')
infisical_db_password=$(SOPS_AGE_KEY_FILE=~/.sops/age/keys.txt sops -d secrets/backbone-01.yaml | rg -o "infisical-db-password: (.*)$" -r '$1')
infisical_encryption_key=$(SOPS_AGE_KEY_FILE=~/.sops/age/keys.txt sops -d secrets/backbone-01.yaml | rg -o "infisical-encryption-key: (.*)$" -r '$1')
infisical_auth_secret=$(SOPS_AGE_KEY_FILE=~/.sops/age/keys.txt sops -d secrets/backbone-01.yaml | rg -o "infisical-auth-secret: (.*)$" -r '$1')

GITEA_DB_PASSWORD="$gitea_db_password" \
INFISICAL_DB_PASSWORD="$infisical_db_password" \
INFISICAL_ENCRYPTION_KEY="$infisical_encryption_key" \
INFISICAL_AUTH_SECRET="$infisical_auth_secret" \
envsubst < manifests/backbone/cnpg.yaml | kubectl apply -f -
```

If you prefer to keep secrets out of the chart values, set them via a k8s secret and patch
the deployment after install.

Replace all `REPLACE_ME` values in `manifests/backbone/cnpg.yaml` before applying.

## Ingress

Install ingress-nginx (ClusterIP):

```sh
nix build .#helmCharts.x86_64-linux.all.ingress-nginx
helm upgrade --install ingress-nginx ./result/*.tgz -n ingress-nginx --create-namespace
```

Cloudflare Tunnel should include a wildcard rule:

```
*.quadtech.dev -> http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
```

## Argo CD

```sh
nix build .#helmCharts.x86_64-linux.all.argocd
helm upgrade --install argocd ./result/*.tgz -n argocd --create-namespace
```

## Gitea

```sh
nix build .#helmCharts.x86_64-linux.all.gitea
helm upgrade --install gitea ./result/*.tgz -n gitea --create-namespace
```

## Verdaccio

```sh
nix build .#helmCharts.x86_64-linux.all.verdaccio
helm upgrade --install verdaccio ./result/*.tgz -n verdaccio --create-namespace
```

## Infisical

```sh
nix build .#helmCharts.x86_64-linux.all.infisical
helm upgrade --install infisical ./result/*.tgz -n infisical --create-namespace
```

## Endpoints

- https://argocd.quadtech.dev
- https://gitea.quadtech.dev
- https://verdaccio.quadtech.dev
- https://infisical.quadtech.dev

## Notes

- `lib/helm/charts/verdaccio.nix` and `lib/helm/charts/infisical.nix` vendor
  upstream charts via `downloadHelmChart` with pinned hashes.
- If a chart is updated upstream, update the version and hash in those files.
