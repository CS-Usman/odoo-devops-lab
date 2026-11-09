# Automated production backups (CronJob)

Nightly **pg_dump** (Azure PostgreSQL FQDN from `odoo-db` secret) plus **filestore** tarball from the prod **Azure File RWX** PVC, uploaded to Blob with **workload identity** (no storage account key on the pod).

## Install

```bash
terraform apply   # creates backup managed identity + Blob RBAC
./scripts/install-backup-cronjob.sh
```

GitOps: Argo CD app `odoo-backup` syncs the CronJob and upload script. **Always run the install script once** so `ServiceAccount` and `odoo-backup-config` get Terraform outputs (Argo ignores those fields after that).

| Object | Purpose |
|--------|---------|
| `CronJob/odoo-backup` | Schedule `0 2 * * *` (02:00 UTC) |
| `ServiceAccount/odoo-backup` | Workload identity → Blob Data Contributor |
| `ConfigMap/odoo-backup-config` | Storage account + container names + client ID |
| PVC `odoo-prod-filestore-rwx` | Read-only mount for filestore archive |

Manual one-shot (same as a CronJob run):

```bash
kubectl -n odoo create job --from=cronjob/odoo-backup odoo-backup-manual-$(date +%s)
kubectl -n odoo logs -f job/odoo-backup-manual-...
```

**Disaster recovery:** [docs/backup/README.md](../../docs/backup/README.md) — restore scenarios, platform rebuild, RPO/RTO, limitations.
