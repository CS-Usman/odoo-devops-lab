# Secrets — Azure Key Vault (default) or Vault (optional)

## Default path (recommended)

```text
Terraform Key Vault  →  seed-keyvault-secrets.sh  →  External Secrets Operator  →  K8s Secrets  →  Odoo / PgBouncer
```

| Step | Command |
|------|---------|
| 1 | `terraform apply` (creates Key Vault + ESO managed identity) |
| 2 | `export DB_USER=... DB_PASSWORD=... STAGING_DB_PASSWORD=...` |
| 3 | `./scripts/seed-keyvault-secrets.sh` |
| 4 | `./scripts/install-external-secrets-azure.sh` |

GitOps extras:

- `k8s/argocd/applications/external-secrets.yaml` — ESO chart + `externalsecret-*-azurekv.yaml`
- Apply **ClusterSecretStore** once via `install-external-secrets-azure.sh` (vault URL comes from Terraform output).

Kubernetes secrets created:

| Secret | Consumers |
|--------|-----------|
| `odoo-db` | odoo-prod, pgbouncer |
| `odoo-staging-db` | odoo-staging |
| `postgres-staging-auth` | postgres-staging StatefulSet |

## Fallback (first boot, no Key Vault yet)

```bash
./scripts/seed-aks-db-secret.sh
```

Same keys in etcd — fine for a quick test; rotate and move to Key Vault for anything persistent.

## Optional: HashiCorp Vault

See [docs/vault/README.md](../vault/README.md) and `k8s/external-secrets/externalsecret-*` (Vault property refs). Use **either** Azure KV **or** Vault, not both stores fighting the same secret names.
