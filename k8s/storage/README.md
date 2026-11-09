# Storage — Azure Blob filestore

## Plain English (the “blob issue”)

Odoo stores uploads (PDFs, images, attachments) on **disk** called the **filestore**, separate from PostgreSQL.

In your lab today, the **running pod** uses a **Kubernetes PVC** — one disk attached to **one pod** at a time (**ReadWriteOnce**). That is simple and cheap, but it means:

- You cannot safely run **two prod web pods** on the same filestore unless they share storage.
- **Azure Blob** is your **off-cluster copy** of that filestore (backup + staging refresh), not always mounted live in every pod.

So: **database in Azure Postgres**, **live files on PVC**, **canonical copy in Blob**. Until you mount Blob inside the pod (Blob Fuse CSI) or sync on a schedule, scaling web replicas will hit “wrong or missing attachments” — that is the blob vs PVC gap, not a broken storage account.

---

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
