# Backups and restore

## Production (Azure Postgres + Blob)

| Component | Method |
|-----------|--------|
| PostgreSQL | `pg_dump` → Azure FQDN (TLS) |
| Filestore | Pod archive → `odoo-backups/YYYY-MM-DD/` and `./scripts/sync-filestore-blob.sh push prod` |

```bash
./scripts/backup.sh
```

## Staging refresh (not Azure DB)

Staging uses **in-cluster Postgres**. To replace it with production data:

```bash
./scripts/refresh-staging-from-prod.sh
# or
./scripts/restore-staging.sh live
```

From a **dated backup** only (into staging cluster DB):

```bash
./scripts/restore-staging.sh YYYY-MM-DD
```

Production Azure Postgres is **never** overwritten by staging scripts.
