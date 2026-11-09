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

**Fresh start (old VM lab or deleted resource group):** archive local state so Terraform does not reference `vm-odoo-lab` and other removed resources:

```bash
cd terraform
mv terraform.tfstate "terraform.tfstate.legacy.$(date +%Y%m%d)" 2>/dev/null || true
mv terraform.tfstate.backup "terraform.tfstate.backup.legacy" 2>/dev/null || true
terraform init
terraform plan
terraform apply
```

**`terraform.tfvars` names:** replace example suffixes — Postgres `psql-odoo-devops-changeme402` (lowercase/hyphens), storage `stodoodevops402` (lowercase letters/numbers only, 3–24 chars). Do not copy literal `UNIQUE` or uppercase from old examples.

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

./scripts/seed-keyvault-secrets.sh    # preferred (Key Vault + ESO)
# or: ./scripts/seed-aks-db-secret.sh
./scripts/install-external-secrets-azure.sh
./scripts/bootstrap-aks.sh
./scripts/install-ingress.sh
export LETSENCRYPT_EMAIL='you@example.com' && ./scripts/install-cert-manager.sh
```

Set `ingress.enabled`, host, and TLS in `helm/odoo/environments/production/ingress.yaml` (and staging on branch `staging`). Push → Argo sync `odoo-prod` / `odoo-staging`. Details: [aks/INGRESS.md](aks/INGRESS.md).

## 8. GitOps (recommended)

```bash
./scripts/install-argocd.sh
kubectl apply -f k8s/argocd/applications/
```

In Argo UI (port-forward):

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:80
```

Sync order: `postgres-staging` → `pgbouncer` → `odoo-prod` → `odoo-staging` → `odoo-backup`.

## 9. Automated backups (disaster recovery)

After prod is running and `odoo-prod-filestore-rwx` exists:

```bash
./scripts/install-backup-cronjob.sh
kubectl -n odoo create job --from=cronjob/odoo-backup odoo-backup-test-$(date +%s)
```

Nightly **02:00 UTC** on the cluster. Restore and DR scenarios: **[backup/README.md](backup/README.md)**.

## 10. First staging data from production

After prod pods run and Azure DB is initialized (first Odoo start / module install):

```bash
./scripts/refresh-staging-from-prod.sh
```

## 11. CI / image pull (when ready)

- GitHub Actions pushes to GHCR.
- Create `kubectl -n odoo create secret docker-registry ghcr-pull ...` if the image is private.
- See [cicd/README.md](cicd/README.md).

## 12. Smoke test

Port-forward (fallback):

```bash
kubectl -n odoo port-forward svc/odoo-prod 8069:8069
kubectl -n odoo port-forward svc/odoo-staging 8071:8069
```

Public HTTPS (after [INGRESS.md](aks/INGRESS.md) — replace with your LB IP):

```bash
SMOKE_URL=https://134-33-199-248.sslip.io ./scripts/smoke-test.sh
STAGING_SMOKE_URL=https://staging.134.33.199.248.nip.io ./scripts/smoke-test.sh
```

Monitoring: `kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80` → Explore → Loki → `{namespace="odoo"}`.

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
| **AKS `InsufficientVCPUQuota`** | Use smaller `aks_node_vm_size` (e.g. `Standard_D2s_v3` or `Standard_B2s`); or [request quota](https://learn.microsoft.com/en-us/azure/quotas/view-quotas) for **eastus** |
| **AKS `AvailabilityZoneNotSupported` (eastus)** | Set `aks_availability_zones = []` in tfvars (default in repo) — do not use `["1","2"]` in East US |
| **Postgres `Version should be in: []` in eastus** | Often **not** SKU/version — run `az postgres flexible-server list-skus --location eastus` and check **`OfferRestricted: Enabled`** / *Provisioning is restricted in this region*. Open a **quota/limit** support ticket to allow **PostgreSQL Flexible Server in East US**, or redeploy the stack in **eastus2** (unrestricted). |
| `kubectl` forbidden | Re-run `az aks get-credentials` |
| Pods `ImagePullBackOff` | GHCR secret or build/push image |
| Staging DB empty | Run `refresh-staging-from-prod.sh` after prod exists |

Architecture: [aks/ARCHITECTURE.md](aks/ARCHITECTURE.md) · Scripts: [../scripts/README.md](../scripts/README.md)
