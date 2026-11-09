# Runbook — operations

## Disaster recovery (quick links)

| Situation | Action |
|-----------|--------|
| Bad prod data | [backup/README.md](backup/README.md) → `./scripts/restore.sh YYYY-MM-DD` |
| Test recovery | `./scripts/restore-staging.sh YYYY-MM-DD` |
| Backup failed | `kubectl -n odoo logs job/<name> -c upload` (or `-c pg-dump` / `filestore-archive`) |
| Rebuild AKS | Below + restore from Blob if DB corrupted |

Full DR scenarios, RPO/RTO, drills: **[backup/README.md](backup/README.md)**.

## Rebuild platform (Terraform)

```bash
cd terraform
terraform plan
terraform apply
az aks get-credentials -g rg-odoo-devops-lab -n aks-odoo-devops-lab --overwrite-existing
./scripts/seed-keyvault-secrets.sh
./scripts/install-external-secrets-azure.sh
./scripts/bootstrap-aks.sh
./scripts/install-argocd.sh
kubectl apply -f k8s/argocd/applications/
./scripts/install-backup-cronjob.sh
```

Restore application data from Blob if Postgres or filestore were lost: [backup/README.md](backup/README.md).

## Deploy failed (GitHub Actions)

1. Check **build** job — Trivy or push errors.
2. Check **gitops** job — commit of `image-tag.yaml`.
3. Argo CD UI — sync status for `odoo-prod` / `pgbouncer`.
4. `kubectl -n odoo get pods,events`
5. `SMOKE_URL=https://... ./scripts/smoke-test.sh` when ingress is ready.

## Database connection exhaustion

1. Check PgBouncer pods: `kubectl -n odoo get pods -l app.kubernetes.io/name=pgbouncer`
2. Scale Odoo web replicas down temporarily if needed.
3. Review Azure Postgres connection metrics.

## Node failure (AKS)

1. `kubectl get nodes`
2. `kubectl -n odoo get pods -o wide`
3. Wait for scheduler; verify PDB keeps minimum web pods.
4. Nightly backup CronJob runs on cluster—unaffected by a single node drain if scheduling succeeds.

## Backup CronJob unhealthy

1. `kubectl -n odoo get cronjob odoo-backup`
2. `kubectl -n odoo get jobs -l app.kubernetes.io/name=odoo-backup --sort-by=.metadata.creationTimestamp`
3. Logs: `kubectl -n odoo logs job/<job> --all-containers`
4. Re-run install if identity/config drifted: `./scripts/install-backup-cronjob.sh`
5. Manual fallback from VM: `./scripts/backup.sh` (needs `.env` + `AZURE_STORAGE_KEY` or az login)

## Vault sealed (if used)

Unseal Vault per your policy; restart ESO if secrets stop syncing.
