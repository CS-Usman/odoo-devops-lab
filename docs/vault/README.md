# Vault + External Secrets

Secrets in **Vault KV**; **External Secrets Operator** syncs to Kubernetes for Odoo and PgBouncer.

## Architecture

```text
Vault (cluster or external)
  secret/odoo/prod     → DB_HOST (PgBouncer), POSTGRES_HOST, DB_USER, DB_PASSWORD, POSTGRES_DB
  secret/odoo/staging  → in-cluster postgres-staging (not Azure)
  secret/odoo/backup   → Azure Blob (optional)

External Secrets Operator → k8s Secrets: odoo-db, odoo-staging-db

Argo CD / Helm → Odoo + PgBouncer pods
```

## Bootstrap

```bash
./scripts/vault-seed-secrets.sh      # after Vault init/unseal
./scripts/vault-bootstrap-k8s-auth.sh  # Kubernetes auth for ESO
./scripts/install-external-secrets.sh
```

For new clusters, prefer **[docs/secrets/README.md](../secrets/README.md)** (Azure Key Vault).
Fallback without any vault: `./scripts/seed-aks-db-secret.sh`.

See `k8s/external-secrets/` for manifests.
