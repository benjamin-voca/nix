# Harbor + Kubernetes Application Deployment Guide

This guide documents the current application deployment flow used on the QuadTech cluster.

It covers:

- pushing a new image to Harbor
- updating an app on Kubernetes
- the current EduKurs deployment pattern
- the recommended shape for new app deployments

## Current environment

- Harbor UI/API hostname: `harbor.quadtech.dev`
- Harbor internal registry: `10.0.0.56:5000`
- Kubernetes ingress IP: `192.168.1.240`
- Cluster admin access on backbone host:

```sh
export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig
```

- QuadNix deploy command:

```sh
nix run github:serokell/deploy-rs -- .#backbone-01 --skip-checks
```

## 1. Push a new image to Harbor

### Recommended image naming

Use immutable tags.

Examples:

- `10.0.0.56:5000/library/edukurs:20260315-2`
- `10.0.0.56:5000/library/orkestr:20260315-1`

Avoid deploying `latest`.

### Build an amd64 image

From the application repo:

```sh
docker buildx build --platform linux/amd64 -t 10.0.0.56:5000/library/<app>:<tag> --load .
```

Example:

```sh
docker buildx build --platform linux/amd64 -t 10.0.0.56:5000/library/edukurs:20260315-2 --load .
```

### Push option A: normal Docker push

If Docker login/push works in your environment:

```sh
docker login harbor.quadtech.dev
docker tag 10.0.0.56:5000/library/<app>:<tag> harbor.quadtech.dev/library/<app>:<tag>
docker push harbor.quadtech.dev/library/<app>:<tag>
```

### Push option B: direct registry upload helper

If normal push is blocked, use the helper script currently stored in EduKurs:

`EduKurs/scripts/upload_registry.py`

Example:

```sh
python3 scripts/upload_registry.py \
  --image 10.0.0.56:5000/library/edukurs:20260315-2 \
  --registry http://10.0.0.56:5000 \
  --repository library/edukurs \
  --tag 20260315-2 \
  --username '<harbor-user>' \
  --password '<harbor-password>'
```

### Verify the pushed tag exists

```sh
curl -u '<harbor-user>:<harbor-password>' http://10.0.0.56:5000/v2/library/<app>/tags/list
```

## 2. Prepare Kubernetes to pull from Harbor

Each namespace that pulls private Harbor images needs a registry secret.

Example:

```sh
kubectl create secret docker-registry harbor-registry \
  --namespace <namespace> \
  --docker-server=10.0.0.56:5000 \
  --docker-username='<harbor-user>' \
  --docker-password='<harbor-password>' \
  --docker-email='infra@quadtech.dev'
```

Reference it from the pod spec:

```yaml
spec:
  imagePullSecrets:
    - name: harbor-registry
```

## 3. Deploy or update an application on Kubernetes

### Minimal manifest set

For a normal web app, keep these files together:

- `namespace.yaml`
- `service-account.yaml`
- `deployment.yaml`
- `service.yaml`
- `ingress.yaml`
- optional database manifests (`cnpg-cluster.yaml`)
- optional app secret manifests if managed declaratively

### Update the image tag

Edit the deployment image:

```yaml
containers:
  - name: app
    image: 10.0.0.56:5000/library/<app>:<tag>
    imagePullPolicy: Always
```

### Apply the manifests

```sh
kubectl apply -f k8s/
```

Or explicitly:

```sh
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/service-account.yaml
kubectl apply -f k8s/cnpg-cluster.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

### Watch rollout

```sh
kubectl -n <namespace> rollout status deployment/<deployment-name>
kubectl -n <namespace> get pods
kubectl -n <namespace> logs deployment/<deployment-name> --since=10m
```

### Validate service and ingress

```sh
kubectl -n <namespace> get svc,ingress
curl -k https://<host>/health
```

## 4. EduKurs reference deployment

EduKurs currently uses:

- namespace: `edukurs`
- app image: Harbor private registry
- DB: CloudNativePG `Cluster`
- probes: `GET /health`
- runtime env from secret: `edukurs-app-secrets`
- image pull secret: `harbor-registry`

Relevant files:

- `EduKurs/k8s/namespace.yaml`
- `EduKurs/k8s/service-account.yaml`
- `EduKurs/k8s/deployment.yaml`
- `EduKurs/k8s/service.yaml`
- `EduKurs/k8s/ingress.yaml`
- `EduKurs/k8s/cnpg-cluster.yaml`

Important notes:

- the old AWS `SecretProviderClass` flow is no longer used here
- the deployment now expects ordinary Kubernetes secrets
- the database service hostname should use CNPG service DNS, not a pod or service IP

Current stable pattern for DB URLs:

```text
postgresql://<user>:<password>@edukurs-db-rw.edukurs.svc.cluster.local:5432/<database>
```

## 5. Recommended new application pattern

For new apps on this cluster:

1. build amd64 image
2. push to Harbor with immutable tag
3. create namespace
4. create `harbor-registry` pull secret in that namespace
5. create runtime secret for the app
6. deploy DB first if needed
7. deploy app/service/ingress
8. verify rollout, logs, and ingress

## 6. Declarative vs imperative changes

Cluster/runtime fixes should end up in git.

Current status:

- QuadNix infrastructure changes are declarative in `QuadNix/`
- app manifests in app repos are declarative
- some runtime secrets are still created imperatively and should be moved to managed secrets later

Recommended next improvement:

- move app secrets and Harbor pull secrets to SOPS-managed manifests or another declarative secret workflow

## 7. Troubleshooting

### ImagePullBackOff

Check:

- image tag exists in Harbor
- namespace has `harbor-registry`
- deployment references the correct registry host

Commands:

```sh
kubectl -n <namespace> describe pod <pod>
kubectl -n <namespace> get secret harbor-registry
```

### App starts but DB migrations fail

Check:

- app secret points to `<cluster>-rw.<namespace>.svc.cluster.local`
- DB cluster is healthy
- app was restarted after DB became available

Commands:

```sh
kubectl -n <namespace> get cluster,po,svc
kubectl -n <namespace> logs deployment/<deployment-name>
kubectl -n <namespace> rollout restart deployment/<deployment-name>
```

### Ingress exists but domain is wrong

Check:

- ingress host matches the desired domain
- external DNS / Cloudflare records point to `192.168.1.240`
- there is no stale redirect at the DNS/CDN layer
