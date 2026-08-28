# Terraform — Azure infra

Three layers: **VM**, **PostgreSQL**, **Blob storage** for backups.

## Overview

| Resource | Purpose |
|----------|---------|
| Linux VM + VNet + NSG | Runs Odoo (Docker), Nginx on :80 |
| PostgreSQL Flexible Server v16 | Managed DB — private, VM-only access |
| Storage account + container | Off-VM backups (db dump + filestore) |

Local dev still uses `docker-compose.yml` (Postgres in Docker). Production VM uses `docker-compose.azure.yml` + Azure Postgres.

---

## Step 1 — VM

Linux VM, network, NSG (SSH, HTTP :80). Odoo ports 8069/8072 are not public — Nginx proxies on :80.

```bash
cd terraform
terraform apply
terraform output public_ip_address
```

---

## Step 2 — Azure PostgreSQL (private)

Managed PostgreSQL in the **same VNet** as the VM. No public internet access.

**Adds:** delegated subnet, private DNS zone, Flexible Server v16, database `odoo_devops_lab`.

```bash
az provider register --namespace Microsoft.DBforPostgreSQL
```

Add to `terraform.tfvars`:

```hcl
postgres_admin_password = "your-password"
```

```bash
terraform apply
terraform output postgres_fqdn
terraform output postgres_database_name
```

**Point Odoo at Azure Postgres (VM):**

```bash
cp .env.azure.example .env
# DB_HOST = postgres_fqdn, DB_USER/DB_PASSWORD from tfvars

sudo docker compose -f docker-compose.azure.yml up -d
```

Open `http://<VM_IP>/`, create or use database `odoo_devops_lab`.

**Test from VM:**

```bash
sudo docker run --rm -e PGPASSWORD="$DB_PASSWORD" postgres:16 \
  psql -h "$DB_HOST" -U odooadmin -d odoo_devops_lab -c 'SELECT 1'
```

---

## Step 3 — Azure Blob (backups)

Storage account + private container `odoo-backups`. Lifecycle deletes blobs after **30 days**.

```bash
az provider register --namespace Microsoft.Storage
terraform apply

terraform output storage_account_name
terraform output storage_container_name
terraform output -raw storage_primary_access_key
```

Put storage values in VM `.env` — see [backup docs](../backup/README.md).

---

## Files

| File | Purpose |
|------|---------|
| `main.tf` | VM, network, NSG |
| `postgres.tf` | Private PostgreSQL Flexible Server |
| `storage.tf` | Blob account, container, lifecycle |
| `variables.tf` | Inputs |
| `outputs.tf` | IP, Postgres FQDN, storage keys |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` (not committed) |

---

## Tear down

```bash
terraform destroy
```

Postgres and storage deletion can take several minutes.
