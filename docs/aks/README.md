# AKS — Odoo platform

**Architecture & full tool stack:** [ARCHITECTURE.md](ARCHITECTURE.md)

## Workloads

| Workload | Replicas | Role |
|----------|----------|------|
| **odoo-prod-web** | **2** | Production HTTP (shared **Azure File RWX** filestore) |
| **pgbouncer** | 2 | Pool **production** → Azure Postgres |
| **postgres-staging** | 1 | Staging Postgres on worker PVC |
| **odoo-staging-web** | 1 | Staging Odoo (disk **RWO** filestore) |

**Nodes:** **2 worker VMs**. **HPA** on prod is configured but **disabled** in env values (fixed 2 replicas).

## Edge & secrets

- **ingress-nginx** + **cert-manager** (Let's Encrypt) — [INGRESS.md](INGRESS.md)
- **Key Vault** + **External Secrets** — [../secrets/README.md](../secrets/README.md)

## Bootstrap

```bash
az aks get-credentials -g rg-odoo-devops-lab -n aks-odoo-devops-lab

./scripts/seed-keyvault-secrets.sh
./scripts/install-external-secrets-azure.sh
./scripts/bootstrap-aks.sh
./scripts/install-argocd.sh
kubectl apply -f k8s/argocd/applications/
./scripts/install-ingress.sh
export LETSENCRYPT_EMAIL='you@example.com' && ./scripts/install-cert-manager.sh
./scripts/install-backup-cronjob.sh
```

Argo order: `postgres-staging` → `pgbouncer` → `odoo-prod` → `odoo-staging` → `monitoring*` → `odoo-backup`.

## Disaster recovery

- **Backup:** CronJob on cluster (nightly) + optional `./scripts/backup.sh` from laptop — [../backup/README.md](../backup/README.md)
- **Restore prod:** `./scripts/restore.sh YYYY-MM-DD`
- **Rehearse on staging:** `./scripts/restore-staging.sh YYYY-MM-DD` (prod Azure untouched)
- **Rebuild AKS:** [../RUNBOOK.md](../RUNBOOK.md)

## Multi-replica prod filestore

```bash
# One-time before scaling prod web to 2:
kubectl -n odoo scale deployment/odoo-prod-web --replicas=0
./scripts/migrate-prod-filestore-rwx.sh
# Then Argo sync odoo-prod (values: azurefile-csi RWX, replicas: 2)
```

## Staging refresh

```bash
./scripts/refresh-staging-from-prod.sh
```

## Storage docs

- Live prod: **Azure File** (Helm `persistence.existingClaim: odoo-prod-filestore-rwx`)
- Blob backups: [k8s/storage/README.md](../../k8s/storage/README.md)
