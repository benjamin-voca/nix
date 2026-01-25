# QuadNix Infrastructure Deployment Guide

This guide walks you through deploying the complete QuadNix infrastructure:
- **Backbone nodes**: Internal services (Gitea, ClickHouse, Grafana, Prometheus)
- **Frontline nodes**: Client applications and workloads

## Architecture Overview

```
QuadNix Infrastructure
├── Backbone (Control Plane + Internal Services)
│   ├── backbone-01  192.168.1.10  (Primary control plane)
│   ├── backbone-02  192.168.1.11  (Secondary control plane, HA)
│   └── Services:
│       ├── Gitea         (gitea.quadtech.dev)
│       ├── ClickHouse    (clickhouse.quadtech.dev)
│       ├── Grafana       (grafana.quadtech.dev)
│       └── Prometheus    (prometheus.quadtech.dev)
│
└── Frontline (Worker Nodes + Client Apps)
    ├── frontline-01  192.168.1.20  (Worker node)
    ├── frontline-02  192.168.1.21  (Worker node)
    └── Client Apps:
        ├── App 1
        ├── App 2
        └── App N
```

## Prerequisites

### Hardware Requirements

**Backbone nodes (each):**
- CPU: 4+ cores
- RAM: 8+ GB
- Disk: 200+ GB SSD

**Frontline nodes (each):**
- CPU: 4+ cores
- RAM: 16+ GB
- Disk: 100+ GB SSD

### Network Requirements

- All nodes on same network (192.168.1.0/24)
- DNS or /etc/hosts entries for service domains
- External access to backbone-01 via mainssh.quadtech.dev

## Step 1: Deploy Backbone Nodes

### 1.1 Build NixOS Configurations

```sh
# Build backbone-01 configuration
nix build .#nixosConfigurations.backbone-01.config.system.build.toplevel

# Build backbone-02 configuration
nix build .#nixosConfigurations.backbone-02.config.system.build.toplevel
```

### 1.2 Deploy to Backbone Nodes

**Option A: Direct deployment (on each node)**

```sh
# On backbone-01
sudo nixos-rebuild switch --flake .#backbone-01

# On backbone-02
sudo nixos-rebuild switch --flake .#backbone-02
```

**Option B: Remote deployment (from your workstation)**

```sh
# Deploy backbone-01
nixos-rebuild switch --flake .#backbone-01 \
  --target-host root@mainssh.quadtech.dev \
  --build-host root@mainssh.quadtech.dev

# Deploy backbone-02
nixos-rebuild switch --flake .#backbone-02 \
  --target-host root@192.168.1.11 \
  --build-host root@192.168.1.11
```

**Option C: Atomic deployment with deploy-rs**

```sh
deploy .#backbone-01
deploy .#backbone-02
```

### 1.3 Verify Kubernetes Control Plane

Wait for Kubernetes to start (may take 2-3 minutes):

```sh
# On backbone-01
kubectl get nodes
kubectl get pods --all-namespaces
```

Expected output:
```
NAME          STATUS   ROLES    AGE   VERSION
backbone-01   Ready    master   1m    v1.28.x
backbone-02   Ready    master   1m    v1.28.x
```

## Step 2: Deploy Frontline Nodes

### 2.1 Deploy Worker Nodes

```sh
# Deploy frontline-01
sudo nixos-rebuild switch --flake .#frontline-01

# Deploy frontline-02
sudo nixos-rebuild switch --flake .#frontline-02
```

### 2.2 Verify Nodes Join Cluster

```sh
# On backbone-01
kubectl get nodes
```

Expected output:
```
NAME           STATUS   ROLES    AGE   VERSION
backbone-01    Ready    master   5m    v1.28.x
backbone-02    Ready    master   5m    v1.28.x
frontline-01   Ready    node     1m    v1.28.x
frontline-02   Ready    node     1m    v1.28.x
```

## Step 3: Deploy Infrastructure Services

### 3.1 Create Namespaces

```sh
kubectl apply -f manifests/backbone/namespaces.yaml
```

### 3.2 Deploy Ingress Controller

```sh
# Build the ingress-nginx chart
nix build .#helmCharts.x86_64-linux.all.ingress-nginx

# Deploy with Helm
helm install ingress-nginx ./result/*.tgz \
  -n ingress-nginx \
  --create-namespace
```

Wait for ingress controller to be ready:

```sh
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### 3.3 Deploy Cert-Manager

```sh
# Build cert-manager chart
nix build .#helmCharts.x86_64-linux.all.cert-manager

# Deploy with Helm
helm install cert-manager ./result/*.tgz \
  -n cert-manager \
  --create-namespace
```

### 3.4 Deploy Monitoring Stack (Prometheus)

```sh
# Build prometheus chart
nix build .#helmCharts.x86_64-linux.all.prometheus

# Deploy with Helm
helm install prometheus ./result/*.tgz \
  -n monitoring \
  --create-namespace
```

### 3.5 Deploy Grafana

```sh
# Build grafana chart
nix build .#helmCharts.x86_64-linux.all.grafana

# Deploy with Helm
helm install grafana ./result/*.tgz \
  -n grafana \
  --create-namespace
```

### 3.6 Deploy Loki

```sh
# Build loki chart
nix build .#helmCharts.x86_64-linux.all.loki

# Deploy with Helm
helm install loki ./result/*.tgz \
  -n loki \
  --create-namespace
```

### 3.7 Deploy Gitea

```sh
# Build gitea chart
nix build .#helmCharts.x86_64-linux.all.gitea

# Deploy with Helm
helm install gitea ./result/*.tgz \
  -n gitea \
  --create-namespace
```

### 3.8 Deploy ClickHouse

```sh
# Deploy ClickHouse operator first
nix build .#helmCharts.x86_64-linux.all.clickhouse-operator
helm install clickhouse-operator ./result/*.tgz \
  -n clickhouse-operator \
  --create-namespace

# Then deploy ClickHouse cluster
nix build .#helmCharts.x86_64-linux.all.clickhouse
helm install clickhouse ./result/*.tgz \
  -n clickhouse \
  --create-namespace
```

## Step 4: Verify Services

### 4.1 Check All Pods

```sh
kubectl get pods --all-namespaces
```

All pods should be in `Running` or `Completed` state.

### 4.2 Check Services

```sh
kubectl get svc --all-namespaces
```

### 4.3 Check Ingress

```sh
kubectl get ingress --all-namespaces
```

Expected ingresses:
- gitea → gitea.quadtech.dev
- grafana → grafana.quadtech.dev
- clickhouse → clickhouse.quadtech.dev
- prometheus → prometheus.quadtech.dev

## Step 5: Configure DNS

Add DNS entries or update `/etc/hosts`:

```
192.168.1.10  gitea.quadtech.dev
192.168.1.10  grafana.quadtech.dev
192.168.1.10  clickhouse.quadtech.dev
192.168.1.10  prometheus.quadtech.dev
```

Or use external DNS service pointing to your ingress load balancer.

## Step 6: Access Services

### Gitea
- URL: https://gitea.quadtech.dev
- Default admin: `gitea_admin` / `changeme` (CHANGE THIS!)
- SSH: `gitea.quadtech.dev:2222`

### Grafana
- URL: https://grafana.quadtech.dev
- Default admin: `admin` / `changeme` (CHANGE THIS!)
- Pre-configured datasources: Prometheus, Loki, ClickHouse

### ClickHouse
- URL: https://clickhouse.quadtech.dev
- HTTP port: 8123
- TCP port: 9000
- Default user: `default` / no password
- Admin user: `admin` / `changeme` (CHANGE THIS!)

### Prometheus
- URL: https://prometheus.quadtech.dev (via Grafana or direct access)
- Grafana already configured to use it

## Step 7: Deploy Client Applications

Client applications run on frontline nodes. Here's an example deployment:

### 7.1 Create Application Namespace

```sh
kubectl create namespace my-app
```

### 7.2 Deploy Application

```yaml
# my-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        ports:
        - containerPort: 8080
      nodeSelector:
        kubernetes.io/role: node  # Run on frontline nodes only
---
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: my-app
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
  tls:
  - secretName: my-app-tls
    hosts:
    - myapp.example.com
```

Apply:
```sh
kubectl apply -f my-app.yaml
```

## Security Considerations

### CRITICAL: Change Default Passwords

All services have default passwords (`changeme`). Update them immediately:

1. **Gitea**: Admin panel → Site Administration → User accounts
2. **Grafana**: Admin panel → Configuration → Users
3. **ClickHouse**: Update via SQL or config

### Using SOPS for Secrets

Store secrets securely with SOPS:

```nix
# secrets/services.yaml (encrypted)
gitea:
  admin_password: "<secure-password>"
grafana:
  admin_password: "<secure-password>"
clickhouse:
  admin_password: "<secure-password>"
```

```nix
# In your service configuration
sops.secrets."gitea/admin-password" = {
  sopsFile = ../secrets/services.yaml;
};
```

### TLS Certificates

Cert-manager will automatically provision Let's Encrypt certificates for configured ingresses.

Ensure your domains point to the ingress controller's external IP.

## Monitoring & Observability

### Access Grafana

1. Navigate to https://grafana.quadtech.dev
2. Login with admin credentials
3. Dashboards are pre-configured for:
   - Kubernetes cluster metrics
   - Node metrics
   - Application metrics (via Prometheus)
   - Logs (via Loki)

### View Logs

Logs are collected by Loki and viewable in Grafana:
1. Grafana → Explore
2. Select "Loki" datasource
3. Query: `{namespace="gitea"}`

### Metrics

Prometheus scrapes metrics from:
- Kubernetes components
- Ingress controller
- All backbone services
- Your applications (if they expose /metrics)

## Maintenance

### Update Services

```sh
# Update flake.lock
nix flake update

# Rebuild and redeploy
nix build .#helmCharts.x86_64-linux.all.gitea
helm upgrade gitea ./result/*.tgz -n gitea
```

### Backup

Important data locations:
- **Gitea**: Persistent volume `/data`
- **ClickHouse**: Persistent volume `/var/lib/clickhouse`
- **Grafana**: Persistent volume `/var/lib/grafana`
- **Prometheus**: Persistent volume `/prometheus`

Set up Velero or similar for Kubernetes backups.

### Scale Services

```sh
# Scale deployments
kubectl scale deployment gitea -n gitea --replicas=3

# Or update Helm values and upgrade
```

## Troubleshooting

### Pods Not Starting

```sh
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Network Issues

```sh
# Check CNI plugin
kubectl get pods -n kube-system

# Test pod-to-pod connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot -- /bin/bash
```

### Storage Issues

```sh
# Check PVCs
kubectl get pvc --all-namespaces

# Check PVs
kubectl get pv
```

### Ingress Not Working

```sh
# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Check ingress resources
kubectl describe ingress <ingress-name> -n <namespace>
```

## Next Steps

1. Set up ArgoCD for GitOps (see `manifests/backbone/argocd/`)
2. Configure external DNS
3. Set up monitoring alerts
4. Configure backup solution
5. Deploy your client applications

## References

- NixOS Manual: https://nixos.org/manual/nixos/stable/
- Kubernetes Documentation: https://kubernetes.io/docs/
- Helm Documentation: https://helm.sh/docs/
- QuadNix Helm Charts: `lib/helm/README.md`
- Cachix Setup: `docs/CACHIX.md`
