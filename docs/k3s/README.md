# Phase 5 — k3s + Helm (prod + staging)

## Databases

| Env | Odoo | PostgreSQL | Cost |
|-----|------|------------|------|
| **Prod** | odoo-prod pod | **Azure Postgres** `odoo_devops_lab` | Managed (existing) |
| **Staging** | odoo-staging pod | **postgres:16 pod on VM** | Free (uses VM disk/RAM) |

Staging DB is like local `docker-compose.yml` Postgres — delete/recreate the pod or wipe `/srv/odoo/postgres-staging` anytime.

```text
http://<VM_IP>/          → odoo-prod     → Azure Postgres
http://<VM_IP>:8080/     → odoo-staging  → postgres-staging (k3s on VM)
```

---

## Step 1 — Terraform (laptop)

Only **NSG port 8080** — no second Azure database:

```bash
cd terraform
terraform plan    # should show NSG rule only (if you cancelled earlier apply)
terraform apply
```

If you accidentally created `odoo_staging` on Azure, remove it in Portal or we can add/remove in Terraform — ask if needed.

---

## Step 2 — Push + pull

```bash
git push origin main
# VM:
cd ~/odoo-devops-lab && git pull && chmod +x scripts/*.sh
```

---

## Step 3 — k3s + migrate (VM)

```bash
./scripts/install-k3s.sh
./scripts/migrate-compose-to-k8s.sh
```

---

## Step 4 — Deploy k8s (VM)

```bash
export GHCR_TOKEN='...'   # if private GHCR
./scripts/deploy-k8s.sh
./scripts/seed-staging.sh   # copy prod → staging (Azure → VM postgres)
```

---

## Wipe / recreate staging only

```bash
kubectl -n odoo delete deployment postgres-staging odoo-staging
sudo rm -rf /srv/odoo/postgres-staging /srv/odoo/staging
./scripts/deploy-k8s.sh
./scripts/seed-staging.sh
```

No Azure cost impact.

---

## Files

| Path | Purpose |
|------|---------|
| `k8s/postgres-staging.yaml` | Staging Postgres pod on VM |
| `helm/odoo/values-prod.yaml` | Azure DB |
| `helm/odoo/values-staging.yaml` | VM postgres-staging service |
