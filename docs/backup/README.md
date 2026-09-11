# Backups — Azure Postgres + filestore → Blob

Off-VM backups so losing the VM does not lose Odoo data.

## Overview

| What | Where it lives | Backup artifact |
|------|----------------|-----------------|
| **Database** | Azure PostgreSQL Flexible Server (`odoo_devops_lab`) | `db.dump` via `pg_dump` |
| **Attachments** | Docker volume on VM (`/var/lib/odoo/filestore/odoo_devops_lab`) | `filestore.tar.gz` |

Both upload to **Azure Blob** (Terraform-managed storage account). Azure Postgres also has 7-day managed backups (DB only — no filestore).

Blob layout:

```text
odoo-backups/
  YYYY-MM-DD/
    db.dump
    filestore.tar.gz
```

Blobs older than **30 days** are deleted automatically (Terraform lifecycle policy).

Scripts: `scripts/backup.sh`, `scripts/restore.sh`, `scripts/restore-staging.sh` (Phase 8 drill).

---

## Step 1 — Terraform (laptop)

```bash
az provider register --namespace Microsoft.Storage
cd terraform
terraform apply
```

Get values for VM `.env`:

```bash
terraform output storage_account_name
terraform output storage_container_name
terraform output -raw storage_primary_access_key
```

See [terraform docs](../terraform/README.md#step-3--azure-blob-backups) for storage details.

---

## Step 2 — VM `.env`

Add to `~/odoo-devops-lab/.env`:

```env
AZURE_STORAGE_ACCOUNT=stodoodevopslab
AZURE_STORAGE_CONTAINER=odoo-backups
AZURE_STORAGE_KEY=<from terraform output>
ODOO_DB_NAME=odoo_devops_lab
```

---

## Step 3 — Azure CLI on VM (once)

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

---

## Step 4 — Run backup

Uses **`postgres:16` Docker client** for dump/restore (matches Azure Postgres 16). Filestore is archived **inside the Odoo container** (avoids host volume permission issues).

```bash
cd ~/odoo-devops-lab
chmod +x scripts/backup.sh scripts/restore.sh
./scripts/backup.sh
```

Verify in Blob:

```bash
az storage blob list \
  --account-name "$AZURE_STORAGE_ACCOUNT" \
  --container-name odoo-backups \
  --output table
```

---

## Step 5 — Weekly cron

```bash
sudo touch /var/log/odoo-backup.log
sudo chown azureuser:azureuser /var/log/odoo-backup.log

sudo tee /etc/cron.d/odoo-backup << 'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 2 * * 0 azureuser /home/azureuser/odoo-devops-lab/scripts/backup.sh >> /var/log/odoo-backup.log 2>&1
EOF
```

Runs every **Sunday 02:00 UTC**. Check: `tail /var/log/odoo-backup.log`

---

## Restore prod (same VM / Azure DB)

```bash
./scripts/restore.sh YYYY-MM-DD
```

Stops Odoo, restores DB + filestore, starts Odoo. Type `yes` to confirm.

---

## Phase 8 — Restore prod backup into staging (k3s)

Proves Blob backups are usable without touching prod.

```bash
# 1. Backup prod (Azure Postgres + /srv/odoo/prod filestore → Blob)
./scripts/backup.sh

# 2. Restore that date into staging (postgres-staging pod + /srv/odoo/staging)
./scripts/restore-staging.sh YYYY-MM-DD
```

Verify on **http://&lt;VM_IP&gt;:8080/** — attachments/images from prod should appear.

Direct prod → staging copy (no Blob): `./scripts/seed-staging.sh`
