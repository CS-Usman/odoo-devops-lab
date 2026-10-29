# Storage — Azure Blob filestore

Odoo attachments/filestore use **Azure Blob** (not Azure Files):

| Container | Purpose |
|-----------|---------|
| `odoo-backups` | Dated `pg_dump` + filestore archives |
| `odoo-prod-filestore` | Live prod filestore snapshot (`filestore.tar.gz`) |
| `odoo-staging-filestore` | Staging copy after `refresh-staging-from-prod.sh` |

Terraform creates these on the storage account from `terraform output storage_account_name`.

## Production (multi pod)

Mount the **prod** blob container with [Blob Fuse CSI](https://learn.microsoft.com/en-us/azure/storage/blobs/azure-blob-fuse-2) so **odoo-prod-web** replicas share the same path, or run `./scripts/sync-filestore-blob.sh push prod` on a schedule and after deploys.

Example StorageClass manifest: configure account + container from Terraform outputs (HNS enabled on the storage account).

## Staging (single pod)

Staging Odoo uses a **local PVC** (`managed-csi`) on the cluster. Refresh scripts copy prod filestore **Blob → staging Blob → pod**.
