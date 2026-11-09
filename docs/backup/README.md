# Backups & disaster recovery

This lab separates **live** data (Azure Postgres, Azure File PVC, in-cluster staging) from **recovery copies** in **Azure Blob**. Production is restored from Blob + Terraform/Key Vault—not by “refresh staging” scripts.

## What is protected

| Asset | Live location | Recovery copy |
|-------|---------------|----------------|
| **Prod PostgreSQL** | Azure Flexible Server (VNet-private) | `pg_dump` → `odoo-backups/YYYY-MM-DD/db.dump` |
| **Prod filestore** | PVC `odoo-prod-filestore-rwx` (Azure File) | Same-day `…/filestore.tar.gz` + live `odoo-prod-filestore/filestore.tar.gz` |
| **Staging** | In-cluster Postgres + RWO disk | Refreshed from prod (Blob), not independently backed up |
| **Platform** | Terraform state (local/remote), Key Vault secrets | Re-apply Terraform; re-seed Key Vault; Argo sync from git |

**Azure platform backups (Postgres):** Flexible Server retains automated backups (~14 days by default in Terraform). Use the **Azure portal** for point-in-time restore to a **new** server—this is separate from the lab’s Blob/`restore.sh` path.

## RPO / RTO (lab targets, not SLAs)

| Metric | Typical lab expectation | Notes |
|--------|-------------------------|--------|
| **RPO** (data loss) | **≤ 24 h** | Nightly CronJob **02:00 UTC**; same calendar day **overwrites** if you run manual backup twice |
| **RTO** (restore app) | **~1–3 h** operator time | Depends on dump size, filestore, and whether AKS already exists |

Small databases + sparse filestore (like a fresh lab) often complete backup/restore in **minutes**; large filestores dominate restore time.

## Automated backup (recommended)

CronJob runs **on AKS** (not the ops VM): `pg_dump` → Azure FQDN, filestore from PVC mount, upload via **workload identity**.

```bash
terraform apply                          # backup managed identity + Blob RBAC
./scripts/install-backup-cronjob.sh
kubectl -n odoo create job --from=cronjob/odoo-backup odoo-backup-test-$(date +%s)
kubectl -n odoo get cronjob,job -l app.kubernetes.io/name=odoo-backup
```

Details: [k8s/backup/README.md](../../k8s/backup/README.md).

Verify blobs (storage account from `terraform output storage_account_name`):

```bash
az storage blob list --account-name <account> --container-name odoo-backups \
  --auth-mode login --prefix "$(date -u +%Y-%m-%d)/" -o table
```

## Manual production backup

```bash
./scripts/backup.sh
```

| Component | Method |
|-----------|--------|
| PostgreSQL | `pg_dump` → Azure FQDN (TLS), not PgBouncer |
| Filestore | Tar from prod web pod **or** rely on CronJob PVC mount (see `backup.sh`, `sync-filestore-blob.sh`) |

## Restore scenarios

### 1. Corrupt prod app data (DB and/or filestore)

Use a **dated** Blob backup. **Destructive** on production.

```bash
./scripts/restore.sh YYYY-MM-DD
```

Flow: scale prod Odoo down → `pg_restore` into Azure Postgres → restore filestore → scale up → `sync-filestore-blob.sh push prod`.

### 2. Validate backup without touching prod

Restore into **staging** only:

```bash
./scripts/restore-staging.sh YYYY-MM-DD
# or copy live prod:
./scripts/restore-staging.sh live
./scripts/refresh-staging-from-prod.sh
```

Production Azure Postgres is **never** modified by staging scripts.

### 3. Lost Kubernetes / AKS (app layer)

Postgres and Blob usually survive if the **resource group** still exists:

1. `terraform apply` (or rebuild AKS only if infra intact)
2. `az aks get-credentials …`
3. `./scripts/seed-keyvault-secrets.sh` (if secrets lost) + `./scripts/install-external-secrets-azure.sh`
4. `./scripts/bootstrap-aks.sh` + Argo applications + ingress/cert-manager
5. `./scripts/install-backup-cronjob.sh`
6. If Postgres data is intact: deploy Odoo; **only if DB is bad:** `./scripts/restore.sh YYYY-MM-DD`

### 4. Lost entire resource group / region

**Not fully automated in this lab.** Defaults: Blob **LRS**, Postgres geo-redundant backup **off**. Recovery requires:

- Terraform in a new region/RG (or restore Azure Postgres from geo backup if you enabled it)
- Off-site or GRS copies of Blob if you add them
- Key Vault / secrets from your break-glass copy

Treat this as a **documented gap** for portfolio honesty; see [limitations](#limitations-and-improvements).

## Disaster recovery drill (recommended quarterly)

1. Confirm last CronJob success: `kubectl -n odoo get jobs -l app.kubernetes.io/name=odoo-backup | tail -3`
2. Pick latest `YYYY-MM-DD` in Blob
3. `./scripts/restore-staging.sh YYYY-MM-DD`
4. Open staging URL, smoke-test login/attachments
5. Log date and result in your ops notes

Optional: maintenance-window dry run of `restore.sh` after staging drill passes.

## Staging refresh (not DR on prod)

Staging uses **in-cluster Postgres**. Refresh replaces it with production data:

```bash
./scripts/refresh-staging-from-prod.sh
```

## Limitations and improvements

| Gap | Mitigation (optional) |
|-----|---------------------|
| No alert on failed backup Job | PrometheusRule on failed `odoo-backup` Job; or Azure Monitor |
| Same-day backup key `YYYY-MM-DD` | Add hour suffix or versioning if you need multiple daily points |
| Regional wipe | GRS storage, geo-redundant Postgres, copy Terraform state + KV secrets off-box |
| Restore untested in CI | Periodic drill above; consider GHA that triggers test Job on schedule |
| Small/empty filestore on PVC | CronJob writes stub tarball if `filestore/<db>` missing; attachments still matter once Odoo creates paths |

## Related docs

- [RUNBOOK.md](../RUNBOOK.md) — platform rebuild, node failure
- [k8s/storage/README.md](../../k8s/storage/README.md) — Blob vs live mounts
- [aks/ARCHITECTURE.md](../aks/ARCHITECTURE.md) — DR in the full stack
