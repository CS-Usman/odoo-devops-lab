# Phase 5 — k3s + Helm (prod + staging)

## Databases

| Env | Odoo | PostgreSQL | Cost |
|-----|------|------------|------|
| **Prod** | odoo-prod pod | **Azure Postgres** `odoo_devops_lab` | Managed (existing) |
| **Staging** | odoo-staging pod | **postgres:16 pod on VM** | Free (uses VM disk/RAM) |

Staging DB is like local `docker-compose.yml` Postgres — delete/recreate the pod or wipe `/srv/odoo/postgres-staging` anytime.

```text
http://<VM_IP>/          → odoo-prod     → Traefik :80 → Azure Postgres
http://<VM_IP>:8080/     → odoo-staging  → hostPort 8080 → VM postgres-staging
```

Prod uses k3s **default Traefik** on `:80`. Staging uses **hostPort `8080`** on the pod (no custom Traefik entrypoint — that breaks the bundled chart v40).

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
./scripts/install-k3s.sh   # k3s + Helm + Traefik; safe to re-run
./scripts/migrate-compose-to-k8s.sh
```

If `install-k3s.sh` stopped at “no matching resources found”, k3s is still running — **re-run** the script after `git pull` (it now waits for the node and installs Helm).

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

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `helm: command not found` | Re-run `./scripts/install-k3s.sh` (installs Helm) |
| `no matching resources found` (node wait) | k3s started; re-run `./scripts/install-k3s.sh` |
| `role "azure_pg_admin" does not exist` on seed | `git pull` and re-run `./scripts/seed-staging.sh` (`--no-acl` on dump) |
| Rollout timeout / old replica pending | hostPath needs `Recreate` strategy — `git pull` and re-run deploy |
| Empty `curl :80/devops/health` but pods Running | **Traefik not running** — `./scripts/fix-traefik.sh` then `./scripts/deploy-k8s.sh` |
| `helm-install-traefik` job Error | Remove custom Traefik config: `./scripts/fix-traefik.sh` (deletes `traefik-odoo-config.yaml`) |
| Prod down after migrate | Finish `./scripts/deploy-k8s.sh` — Compose Odoo was stopped on purpose |

---

## Files

| Path | Purpose |
|------|---------|
| `k8s/postgres-staging.yaml` | Staging Postgres pod on VM |
| `scripts/fix-traefik.sh` | Restore default k3s Traefik on `:80` |
| `helm/odoo/values-prod.yaml` | Azure DB + Traefik IngressRoute |
| `helm/odoo/values-staging.yaml` | VM postgres + hostPort `:8080` |
