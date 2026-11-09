# Storage — Azure Blob filestore

## Plain English (the “blob issue”)

Odoo stores uploads (PDFs, images, attachments) on **disk** called the **filestore**, separate from PostgreSQL.

| Environment | Live filestore | Access |
|-------------|----------------|--------|
| **Production** | PVC **`odoo-prod-filestore-rwx`** | **Azure File** (`azurefile-csi`), **ReadWriteMany** — **2** `odoo-prod-web` pods |
| **Staging** | PVC **`odoo-staging-filestore`** | **Azure Disk** (`managed-csi`), **ReadWriteOnce** — **1** web pod |

**Azure Blob** remains the **backup and refresh** layer (not the live mount for prod anymore):

- `odoo-backups`, `odoo-prod-filestore`, `odoo-staging-filestore` containers
- Scripts: `backup.sh`, **CronJob `odoo-backup`**, `restore.sh`, `sync-filestore-blob.sh`, `refresh-staging-from-prod.sh`
- **DR guide:** [docs/backup/README.md](../../docs/backup/README.md)

**One-time prod migration** (disk RWO → Azure File RWX): `./scripts/migrate-prod-filestore-rwx.sh`

---

Odoo attachments/filestore use **Azure Blob** (not Azure Files):

| Container | Purpose |
|-----------|---------|
| `odoo-backups` | Dated `pg_dump` + filestore archives |
| `odoo-prod-filestore` | Live prod filestore snapshot (`filestore.tar.gz`) |
| `odoo-staging-filestore` | Staging copy after `refresh-staging-from-prod.sh` |

Terraform creates these on the storage account from `terraform output storage_account_name`.

## Production (multi pod) — default in this lab

**Azure File RWX** via Helm (`environments/production/values.yaml`). Alternative for advanced labs: [Blob Fuse CSI](https://learn.microsoft.com/en-us/azure/storage/blobs/azure-blob-fuse-2) or scheduled `sync-filestore-blob.sh push prod`.

## Staging (single pod)

Staging Odoo uses a **local PVC** (`managed-csi`) on the cluster. Refresh scripts copy prod filestore **Blob → staging Blob → pod**.

## Disaster recovery (summary)

| Need | Use |
|------|-----|
| Latest off-cluster copy | `odoo-backups/<date>/` + `odoo-prod-filestore/filestore.tar.gz` |
| Restore production | `./scripts/restore.sh YYYY-MM-DD` |
| Rehearse without touching prod | `./scripts/restore-staging.sh YYYY-MM-DD` |

Blob lifecycle (Terraform) trims old dated backups; prod Postgres has separate Azure retention. See [docs/backup/README.md](../../docs/backup/README.md).
