# Frontline - Client Application Manifests

This directory contains Kubernetes manifests for client-facing applications that run on frontline (worker) nodes.

## Node Selector

All client applications should use node selectors to ensure they run on frontline nodes:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/role: node  # Runs on worker nodes (frontline)
```

This ensures:
- Internal services stay on backbone nodes
- Client apps run on dedicated frontline nodes
- Better resource isolation and scaling

## Directory Structure

```
frontline/
├── examples/           Example application deployments
│   ├── web-app.yaml   Simple web application
│   ├── api-app.yaml   API service with database
│   └── worker.yaml    Background worker
├── ingress/           Ingress configurations
└── storage/           Persistent storage claims
```

## Quick Start

### 1. Deploy an Example Application

```sh
# Deploy the web app example
kubectl apply -f examples/web-app.yaml

# Check status
kubectl get pods -n client-apps
kubectl get svc -n client-apps
kubectl get ingress -n client-apps
```

### 2. Access Your Application

The example includes an ingress configuration. Update DNS to point to your ingress controller:

```
myapp.example.com → <ingress-controller-ip>
```

### 3. Scale Your Application

```sh
kubectl scale deployment web-app -n client-apps --replicas=5
```

## Best Practices

### Resource Limits

Always set resource requests and limits:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 1000m
    memory: 512Mi
```

### Health Checks

Configure liveness and readiness probes:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

### Multiple Replicas

Run at least 2 replicas for high availability:

```yaml
spec:
  replicas: 3  # Minimum 2, recommended 3+
```

### Anti-Affinity

Spread pods across nodes:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app: my-app
        topologyKey: kubernetes.io/hostname
```

## Monitoring

All client applications should expose metrics for Prometheus:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

## Logging

Logs are automatically collected by Loki. Use structured logging (JSON) for best results:

```json
{
  "level": "info",
  "msg": "Request processed",
  "method": "GET",
  "path": "/api/users",
  "duration_ms": 42
}
```

## Storage

For persistent storage, create PVCs:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: local-path
```

## Secrets

Use Kubernetes secrets for sensitive data:

```sh
# Create secret
kubectl create secret generic my-app-secrets \
  --from-literal=db-password=<password> \
  -n client-apps

# Reference in deployment
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: my-app-secrets
        key: db-password
```

Or use SOPS for GitOps-friendly secret management.

## See Also

- `examples/` - Example application manifests
- `../backbone/` - Internal infrastructure services
- `../../docs/DEPLOYMENT.md` - Complete deployment guide
