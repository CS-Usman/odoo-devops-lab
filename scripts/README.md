# Scripts

Run from repo root with `kubectl` + `az` + `docker` on your machine.

**First time:** [docs/GETTING-STARTED.md](../docs/GETTING-STARTED.md) · `./scripts/check-prerequisites.sh`

Copy [.env.azure.example](../.env.azure.example) → `.env`.

| Script | Purpose |
|--------|---------|
| **check-prerequisites.sh** | Verify az, terraform, kubectl, helm, docker |
| **seed-aks-db-secret.sh** | Create `odoo-db`, `postgres-staging-auth`, `odoo-staging-db` |
| **bootstrap-aks.sh** | First deploy after Terraform |
| **deploy-aks-apps.sh** | Helm: postgres-staging → pgbouncer → odoo-prod → odoo-staging |
| **backup.sh** | Prod Azure pg_dump + filestore → Blob (dated + prod filestore container) |
| **restore.sh** | Prod restore from dated backup (Azure DB) |
| **refresh-staging-from-prod.sh** | Wipe staging DB/PVC filestore; copy live prod |
| **restore-staging.sh** | `live` → refresh; or `YYYY-MM-DD` from backup blob |
| **sync-filestore-blob.sh** | push prod / copy prod→staging / pull staging |
| **smoke-test.sh** | `SMOKE_URL` (+ optional `STAGING_SMOKE_URL`) |
| **install-argocd.sh** | Argo CD + apply `k8s/argocd/applications/` |
| **install-monitoring.sh** | Prometheus / Grafana stack |
| **install-external-secrets.sh** | ESO + Vault manifests |
| **vault-seed-secrets.sh** / **vault-bootstrap-k8s-auth.sh** | Optional Vault |
| **install-blobfuse-csi.sh** | Pointer to Blob Fuse docs (optional CSI) |

Shared helpers: [lib/common.sh](lib/common.sh)

Typical flow:

```bash
terraform apply
./scripts/seed-aks-db-secret.sh
./scripts/bootstrap-aks.sh
./scripts/refresh-staging-from-prod.sh
SMOKE_URL=https://odoo.example.com ./scripts/smoke-test.sh
```
