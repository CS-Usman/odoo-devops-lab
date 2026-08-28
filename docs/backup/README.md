# Backups — PostgreSQL + filestore → Azure Blob

Off-VM backups so VM loss does not lose Odoo data.

## What gets backed up

| Artifact | Source |
|----------|--------|
| `db.dump` | `pg_dump` of `odoo_devops_lab` (Azure Postgres) |
| `filestore.tar.gz` | `/var/lib/odoo/filestore/odoo_devops_lab` on Docker volume |

Blob layout:

```text
odoo-backups/
  2026-08-28/
    db.dump
    filestore.tar.gz
```

Old blobs auto-delete after **30 days** (Terraform lifecycle policy).

---

## Step 1 — Terraform (laptop)

Register provider once:

```bash
az provider register --namespace Microsoft.Storage
```

Apply storage resources:

```bash
cd terraform
terraform plan
terraform apply
```

Get secrets for VM `.env`:

```bash
terraform output storage_account_name
terraform output storage_container_name
terraform output -raw storage_primary_access_key
```

If storage account name is taken, set `storage_account_name` in `terraform.tfvars` and apply again.

---

## Step 2 — VM `.env` (add blob vars)

```env
AZURE_STORAGE_ACCOUNT=stodoodevopslab
AZURE_STORAGE_CONTAINER=odoo-backups
AZURE_STORAGE_KEY=<from terraform output -raw storage_primary_access_key>
ODOO_DB_NAME=odoo_devops_lab
```

---

## Step 3 — Install Azure CLI on VM (once)

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az version
```

---

## Step 4 — Run backup manually

```bash
cd ~/odoo-devops-lab
chmod +x scripts/backup.sh scripts/restore.sh
./scripts/backup.sh
```

List blobs:

```bash
export AZURE_STORAGE_KEY='...'
az storage blob list \
  --account-name stodoodevopslab \
  --container-name odoo-backups \
  --output table
```

---

## Step 5 — Weekly cron (VM)

```bash
sudo tee /etc/cron.d/odoo-backup << 'EOF'
SHELL=/bin/bash
0 2 * * 0 azureuser /home/azureuser/odoo-devops-lab/scripts/backup.sh >> /var/log/odoo-backup.log 2>&1
EOF
```

---

## Restore (careful)

```bash
./scripts/restore.sh 2026-08-28
```

Type `yes` when prompted. Stops Odoo, restores DB + filestore, starts Odoo.

---

## Azure Postgres managed backup

Terraform Postgres still has **7-day managed backups** (DB only). Blob backups add **filestore** and portable full copies for staging refresh.
