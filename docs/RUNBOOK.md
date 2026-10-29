# Runbook — operations

## Rebuild platform (Terraform)

```bash
cd terraform
terraform plan
terraform apply
az aks get-credentials -g rg-odoo-devops-lab -n aks-odoo-devops-lab --overwrite-existing
./scripts/seed-aks-db-secret.sh
./scripts/bootstrap-aks.sh
```

Restore application data from Blob if needed: [backup/README.md](backup/README.md).

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
3. Wait for scheduler / cluster autoscaler; verify PDB keeps minimum web pods.

## Vault sealed (if used)

Unseal Vault per your policy; restart ESO if secrets stop syncing.
