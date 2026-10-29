# AKS — Odoo platform

**Architecture:** [ARCHITECTURE.md](ARCHITECTURE.md)

## Workloads

| Workload | Replicas | Role |
|----------|----------|------|
| **odoo-prod-web** | 2 (HPA → 4) | Production HTTP |
| **odoo-prod-cron** | 1 | Production cron |
| **pgbouncer** | 2 | Pool **production** → Azure Postgres |
| **postgres-staging** | 1 | Staging Postgres on worker PVC |
| **odoo-staging-web** | 1 | Staging Odoo |

**Nodes:** exactly **2 worker VMs**.

## Bootstrap

```bash
az aks get-credentials -g rg-odoo-devops-lab -n aks-odoo-devops-lab

export POSTGRES_FQDN="$(terraform -chdir=terraform output -raw postgres_fqdn)"
export DB_USER=odooadmin DB_PASSWORD='...' STAGING_DB_PASSWORD='...'
./scripts/seed-aks-db-secret.sh

./scripts/bootstrap-aks.sh
./scripts/install-argocd.sh
kubectl apply -f k8s/argocd/applications/
```

Argo order: `postgres-staging` → `pgbouncer` → `odoo-prod` → `odoo-staging`.

## Staging refresh

```bash
./scripts/refresh-staging-from-prod.sh
```

## Storage

Blob filestore: [k8s/storage/README.md](../../k8s/storage/README.md)
