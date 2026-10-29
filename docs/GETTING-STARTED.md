# Start from scratch (local machine → Azure)

Use this after a **new Azure subscription** (pay-as-you-go). No VM/k3s — only Terraform + AKS.

## 1. Tools on your laptop

| Tool | Check |
|------|--------|
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | `az version` |
| [Terraform](https://developer.hashicorp.com/terraform/install) | `terraform version` (≥ 1.5) |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | `kubectl version --client` |
| [Helm](https://helm.sh/docs/intro/install/) | `helm version` |
| Docker | `docker version` (for `pg_dump` / local Odoo) |

Optional: `./scripts/check-prerequisites.sh`

## 2. Sign in to Azure (local)

```bash
az login
# Browser opens — pick your account

az account list -o table
az account set --subscription "<subscription-id-or-name>"

az account show -o table   # confirm tenant + subscription
```

If you use multiple tenants:

```bash
az login --tenant "<tenant-id>"
```

**Billing:** ensure the subscription is **Active** (pay-as-you-go), not disabled.

## 3. Clone repo and local env file

```bash
cd /path/to/odoo-devops-lab
cp .env.azure.example .env
# Edit .env later after terraform apply (passwords, storage key)
```

Never commit `.env` or `terraform/terraform.tfvars`.

## 4. Terraform (creates Azure resources)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit **`terraform.tfvars`** — use **globally unique** names:

- `postgres_server_name` — suffix e.g. `-u12345`
- `storage_account_name` — lowercase, no dashes, unique
- Strong `postgres_admin_password`

**Fresh subscription:** if you have old `terraform.tfstate` from a deleted subscription, remove or archive it before apply:

```bash
# Only if state points to deleted infra:
# mv terraform.tfstate terraform.tfstate.old
terraform init
terraform plan
terraform apply
```

Save outputs:

```bash
terraform output -raw postgres_fqdn
terraform output storage_account_name
terraform output aks_get_credentials_command
```

## 5. Connect kubectl to AKS

Run the command from Terraform output, or:

```bash
az aks get-credentials \
  -g rg-odoo-devops-lab \
  -n aks-odoo-devops-lab \
  --overwrite-existing

kubectl get nodes   # expect 2 Ready workers
```

Your kubeconfig is on the laptop; you do **not** SSH to cluster nodes for normal work.

## 6. Storage account key (for scripts)

```bash
RG=rg-odoo-devops-lab
SA=$(terraform -chdir=terraform output -raw storage_account_name)
az storage account keys list -g "$RG" -n "$SA" -o tsv --query '[0].value'
```

Put in `.env`:

- `POSTGRES_FQDN` = `terraform output -raw postgres_fqdn`
- `DB_USER` / `DB_PASSWORD` = same as tfvars admin
- `STAGING_DB_PASSWORD` = choose a strong password (in-cluster Postgres only)
- `AZURE_STORAGE_ACCOUNT` / `AZURE_STORAGE_KEY`

## 7. Bootstrap Kubernetes apps

From repo root:

```bash
export POSTGRES_FQDN="$(terraform -chdir=terraform output -raw postgres_fqdn)"
export DB_USER=odooadmin
export DB_PASSWORD='...'
export STAGING_DB_PASSWORD='...'

./scripts/seed-aks-db-secret.sh
./scripts/bootstrap-aks.sh
```

## 8. GitOps (recommended)

```bash
./scripts/install-argocd.sh
kubectl apply -f k8s/argocd/applications/
```

In Argo UI (port-forward):

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:80
```

Sync order: `postgres-staging` → `pgbouncer` → `odoo-prod` → `odoo-staging`.

## 9. First staging data from production

After prod pods run and Azure DB is initialized (first Odoo start / module install):

```bash
./scripts/refresh-staging-from-prod.sh
```

## 10. CI / image pull (when ready)

- GitHub Actions pushes to GHCR.
- Create `kubectl -n odoo create secret docker-registry ghcr-pull ...` if the image is private.
- See [cicd/README.md](cicd/README.md).

## 11. Smoke test

Until Application Gateway + DNS exist:

```bash
kubectl -n odoo port-forward svc/odoo-prod-web 8069:8069
# SMOKE_URL=http://127.0.0.1:8069 ./scripts/smoke-test.sh
```

With public URL:

```bash
SMOKE_URL=https://odoo.example.com ./scripts/smoke-test.sh
```

## Local Odoo only (no Azure cost)

```bash
docker compose up -d --build
# http://localhost:8069
```

## Troubleshooting

| Issue | Action |
|-------|--------|
| `az login` wrong sub | `az account set --subscription ...` |
| Terraform name taken | Change unique suffixes in tfvars |
| `kubectl` forbidden | Re-run `az aks get-credentials` |
| Pods `ImagePullBackOff` | GHCR secret or build/push image |
| Staging DB empty | Run `refresh-staging-from-prod.sh` after prod exists |

Architecture: [aks/ARCHITECTURE.md](aks/ARCHITECTURE.md) · Scripts: [../scripts/README.md](../scripts/README.md)
