# GitOps (Argo CD)

## Install

```bash
az aks get-credentials -g rg-odoo-devops-lab -n aks-odoo-devops-lab
./scripts/install-argocd.sh
```

Applications live in `k8s/argocd/applications/`:

| Application | Helm path |
|-------------|-----------|
| `pgbouncer` | `helm/pgbouncer` |
| `odoo-prod` | `helm/odoo` + production value files |
| `odoo-staging` | `helm/odoo` + `values-staging.yaml` |

## UI access

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:80
# http://127.0.0.1:8081  user: admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo
```

## Sync policy

Production apps use automated sync with prune and self-heal. CI only updates the **image tag** file; Argo applies the rest of the chart from git.

## Source of truth (day 2+)

After Argo CD is installed and Applications are synced:

| Do in git / CI | Do once on cluster (not in git) |
|----------------|--------------------------------|
| Helm value changes, PgBouncer/Odoo chart fixes | `seed-aks-db-secret.sh`, `ghcr-pull` secret |
| Image tag bumps via `docker-build.yml` | DB init jobs, storage keys in `.env` |
| `git push main` → Argo syncs | `terraform apply` for Azure resources |

Avoid `./scripts/deploy-aks-apps.sh` for routine changes once Argo shows **Synced/Healthy** — it bypasses GitOps and fights self-heal.

**Before first Argo sync:** commit and push your branch so the remote matches what you want the cluster to run; otherwise Argo will roll back to old `main`.

## Private repository

```bash
ARGOCD_GITHUB_TOKEN=<pat-with-repo-read> ./scripts/install-argocd.sh
```
