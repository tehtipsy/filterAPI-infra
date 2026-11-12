# filterAPI-infra

DevOps repository for **ERPal** — contains Kubernetes manifests, Nginx reverse proxy configuration, CI/CD deploy pipeline, Prometheus/Grafana monitoring stack, and **Terraform AWS infrastructure**.

Application source code lives in [tehtipsy/filterAPI](https://github.com/tehtipsy/filterAPI).

## Repository Structure

```
filterAPI-infra/
├── terraform/                  # AWS infrastructure as code
│   ├── versions.tf             # Provider/Terraform version constraints, S3 backend template
│   ├── variables.tf            # All input variables
│   ├── main.tf                 # VPC + EKS modules
│   ├── ecr.tf                  # ECR repository + lifecycle policy
│   ├── iam.tf                  # GitHub Actions OIDC provider + IAM role
│   ├── outputs.tf              # Cluster endpoint, ECR URL, OIDC role ARN
│   ├── terraform.tfvars.example
│   └── .gitignore
├── k8s/                        # Kubernetes manifests
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secret.yaml             # Template — no real values committed
│   ├── pvc.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── nginx/
│   └── default.conf            # Nginx reverse proxy config
├── monitoring/
│   ├── prometheus.yml          # Prometheus scrape config
│   ├── docker-compose.yml      # Local monitoring stack
│   └── grafana/
│       └── provisioning/
│           └── datasources/
│               └── prometheus.yml
└── .github/workflows/
    ├── terraform.yml           # Terraform plan + apply pipeline
    └── deploy.yml              # K8s manifest deploy pipeline
```

---

## Terraform — AWS Infrastructure

The `terraform/` directory provisions the full AWS infrastructure for ERPal using the official `terraform-aws-modules` community modules.

| Resource | Details |
|---|---|
| **VPC** | 2 AZs, public + private subnets, single NAT gateway |
| **EKS** | Managed node group, `t3.medium` × 2 nodes (configurable) |
| **ECR** | Private image registry with scan-on-push + 10-image lifecycle policy |
| **IAM OIDC** | GitHub Actions role (no static AWS credentials needed) |

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured (`aws configure`)
- An S3 bucket for remote state (recommended before first apply)

### Quick Start

```bash
cd terraform/

# Copy and edit variable values
cp terraform.tfvars.example terraform.tfvars

# Initialise providers (optionally configure S3 backend in versions.tf first)
terraform init

# Preview all changes
terraform plan

# Apply
terraform apply
```

After apply, configure `kubectl`:

```bash
$(terraform output -raw configure_kubectl)
```

Then apply the Kubernetes manifests (see [Kubernetes Setup](#kubernetes-setup) below).

### Remote State (Recommended)

Create the S3 bucket and DynamoDB lock table once:

```bash
aws s3api create-bucket \
  --bucket your-terraform-state-bucket \
  --region us-east-1

aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Then uncomment and fill in the `backend "s3"` block in `terraform/versions.tf`, and re-run `terraform init`.

### Connecting GitHub Actions to AWS (OIDC)

The Terraform configuration creates an OIDC identity provider and a scoped IAM role so GitHub Actions **never needs static AWS credentials**.

After `terraform apply`, grab the outputs:

```bash
terraform output github_actions_role_arn   # → add as AWS_ROLE_ARN secret
terraform output ecr_repository_url        # → add as IMAGE_DOCKER_REPO secret
terraform output aws_region                # → add as AWS_REGION secret
```

Add these three values as repository secrets in **both** `tehtipsy/filterAPI` and `tehtipsy/filterAPI-infra`.

The `terraform.yml` CI pipeline then runs automatically on every push/PR that changes files under `terraform/`:

| Step | On push to `main` | On pull request |
|---|---|---|
| fmt / validate | ✓ | ✓ |
| plan (with PR comment) | ✓ | ✓ |
| apply | ✓ | ✗ |

---

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

### 3. Apply all remaining manifests

```bash
kubectl apply -f k8s/ -n erpal
```

### 4. Verify the deployment

```bash
kubectl get pods -n erpal
kubectl rollout status deployment/erpal-app -n erpal
kubectl get ingress -n erpal
```

---

## Nginx

`nginx/default.conf` configures a reverse proxy to the `erpal-service` ClusterIP. The `/metrics` path is restricted to RFC-1918 ranges only. For the Nginx Ingress Controller the `k8s/ingress.yaml` already sets `ingressClassName: nginx`.

---

## Monitoring

### Local stack (Prometheus + Grafana)

```bash
cd monitoring/
docker compose up -d
```

- Prometheus: http://localhost:9090
- Grafana: http://localhost:3001 (admin / admin)

The Grafana Prometheus datasource is auto-provisioned. Import dashboard ID **11956** (Node.js) to visualise ERPal's `http_requests_total` and `http_request_duration_seconds` metrics.

### Cluster scraping

Deployment pods are annotated so Prometheus auto-discovers them via Kubernetes service discovery:

```yaml
prometheus.io/scrape: "true"
prometheus.io/port: "3000"
prometheus.io/path: "/metrics"
```

---

## Best Practices Implemented

| Area | Detail |
|---|---|
| **Security** | Non-root container (`runAsUser: 1000`); OIDC auth (no static credentials); secrets never committed |
| **Reliability** | Liveness + readiness probes; `RollingUpdate` deployment strategy; `replicas: 2` |
| **Resources** | CPU/memory requests and limits on every container |
| **Storage** | SQLite data persisted via `ReadWriteOnce` PVC |
| **Observability** | Prometheus annotations; `/metrics` endpoint; Grafana dashboards |
| **IaC** | All AWS infra in Terraform; `.tfstate` excluded from git; example tfvars only |
