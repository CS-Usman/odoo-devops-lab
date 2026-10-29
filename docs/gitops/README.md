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

## Private repository

```bash
ARGOCD_GITHUB_TOKEN=<pat-with-repo-read> ./scripts/install-argocd.sh
```
