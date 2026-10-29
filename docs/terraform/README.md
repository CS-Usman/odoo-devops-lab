# Terraform — Azure platform

| Resource | Purpose |
|----------|---------|
| Resource group + VNet | Network foundation |
| **AKS** | **2 worker VMs** (fixed pool) |
| **PostgreSQL Flexible Server** | **Production database only** (`odoo_devops_lab`) |
| **Storage account (Blob, HNS)** | Backups + `odoo-prod-filestore` + `odoo-staging-filestore` |

Staging PostgreSQL is **not** in Terraform — it runs on AKS (`helm/postgres-staging`).

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Outputs

```bash
terraform output aks_get_credentials_command
terraform output -raw postgres_fqdn
terraform output storage_account_name
terraform output odoo_prod_filestore_container_name
```

See [k8s/storage/README.md](../../k8s/storage/README.md) for Blob Fuse / filestore sync.

## Cost note

AKS + GP Postgres + storage incur ongoing charges. Requires active **pay-as-you-go** Azure.
