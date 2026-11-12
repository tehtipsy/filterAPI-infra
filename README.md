# filterAPI-infra

DevOps repository for **ERPal** — contains Kubernetes manifests, Nginx reverse proxy configuration, CI/CD deploy pipeline, and Prometheus/Grafana monitoring stack.

Application source code lives in [tehtipsy/filterAPI](https://github.com/tehtipsy/filterAPI).

## Repository Structure

```
filterAPI-infra/
├── k8s/                    # Kubernetes manifests
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secret.yaml         # Template — no real values committed
│   ├── pvc.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── nginx/
│   └── default.conf        # Nginx reverse proxy config
├── monitoring/
│   ├── prometheus.yml      # Prometheus scrape config
│   ├── docker-compose.yml  # Local monitoring stack
│   └── grafana/
│       └── provisioning/
│           └── datasources/
│               └── prometheus.yml
└── .github/workflows/
    └── deploy.yml          # K8s deploy pipeline
```

## Prerequisites

- `kubectl` configured against your cluster
- Docker Hub account (or any OCI registry)
- A running Kubernetes cluster (Minikube / Kind / K3s / cloud)
- Nginx Ingress Controller installed on the cluster

## Kubernetes Setup

### 1. Create the namespace

```bash
kubectl apply -f k8s/namespace.yaml
```

### 2. Create the secret

Do **not** commit real secrets. Create the secret from your local `.env` file:

```bash
kubectl create secret generic erpal-secrets \
  --from-env-file=.env \
  -n erpal \
  --dry-run=client -o yaml | kubectl apply -f -
```

Or use the template as a reference:
```bash
# Edit k8s/secret.yaml to fill in values, then:
kubectl apply -f k8s/secret.yaml -n erpal
```

### 3. Apply all remaining manifests

```bash
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/pvc.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

Or apply the whole directory at once:
```bash
kubectl apply -f k8s/ -n erpal
```

### 4. Verify the deployment

```bash
kubectl get pods -n erpal
kubectl rollout status deployment/erpal-app -n erpal
kubectl get ingress -n erpal
```

## Nginx

The `nginx/default.conf` configures a reverse proxy to the `erpal-service` ClusterIP. The `/metrics` path is restricted to the internal network only.

To use this with Nginx Ingress Controller, the Ingress resource in `k8s/ingress.yaml` already references the `nginx` ingressClassName. For a standalone Nginx pod or bare-metal deployment, mount `nginx/default.conf` as a ConfigMap volume.

## Monitoring

### Local stack (Prometheus + Grafana via Docker Compose)

```bash
cd monitoring/
docker compose up -d
```

- Prometheus: http://localhost:9090
- Grafana: http://localhost:3001 (admin / admin)

The Grafana Prometheus datasource is auto-provisioned. Import a Node.js dashboard (e.g. Grafana Dashboard ID **11956**) to visualise ERPal metrics.

### Cluster scraping

The Deployment pods are annotated with:
```yaml
prometheus.io/scrape: "true"
prometheus.io/port: "3000"
prometheus.io/path: "/metrics"
```

The `monitoring/prometheus.yml` uses Kubernetes service discovery to scrape all annotated pods in the `erpal` namespace automatically.

## CI/CD Pipeline

The `.github/workflows/deploy.yml` pipeline triggers on every push to `main` and applies the K8s manifests in order. It requires the `KUBECONFIG` secret (base64-encoded kubeconfig).

```bash
# Encode your kubeconfig for the secret:
base64 -w 0 ~/.kube/config
```

Add the output as the `KUBECONFIG` repository secret in GitHub Settings → Secrets.

## Best Practices Implemented

- **Non-root container**: Deployment runs as `appuser` (UID 1000) with `runAsNonRoot: true`
- **Resource limits**: CPU and memory requests/limits set on all containers
- **Health probes**: Liveness and readiness probes on `/metrics`
- **Namespace isolation**: All resources scoped to the `erpal` namespace
- **Secret management**: Secrets never committed — created from env file or external secret manager
- **Persistent storage**: SQLite data persisted via a PVC (ReadWriteOnce)
