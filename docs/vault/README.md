# Phase 6 — Vault + External Secrets

**Status: Done.** Secrets live in Vault KV; External Secrets Operator syncs them into k8s for Odoo pods.

## Architecture

```text
Vault (systemd on VM, :8200)
  secret/odoo/prod     → DB_HOST, DB_USER, DB_PASSWORD
  secret/odoo/staging  → staging DB creds + POSTGRES_DB
  secret/odoo/backup   → Azure Blob key (optional)

External Secrets Operator
  → k8s Secrets: odoo-db, odoo-staging-db, postgres-staging

deploy-k8s.sh (CI)
  → waits for ESO secrets, Helm upgrade only (no kubectl create secret for DB)
```

## One-time bootstrap (VM)

```bash
export VAULT_ADDR='https://127.0.0.1:8200'
export VAULT_CACERT='/opt/vault/tls/tls.crt'

# After init + unseal:
./scripts/vault-seed-secrets.sh
./scripts/vault-bootstrap-k8s-auth.sh
./scripts/install-external-secrets.sh
```

## After VM reboot

Vault seals on restart:

```bash
vault operator unseal <key>
```

ESO keeps working once Vault is unsealed.

## Rotate a secret

```bash
vault kv put secret/odoo/prod DB_PASSWORD='new-password' ...
# ESO refreshes within refreshInterval (1h) or force:
kubectl -n odoo annotate externalsecret odoo-db force-sync=$(date +%s) --overwrite
kubectl -n odoo rollout restart deployment/odoo-prod
```

## Files

| Path | Purpose |
|------|---------|
| `scripts/vault-seed-secrets.sh` | `.env` → Vault KV (one-time / re-seed) |
| `scripts/vault-bootstrap-k8s-auth.sh` | K8s auth + odoo-read policy + ESO role |
| `scripts/install-external-secrets.sh` | Helm ESO + ExternalSecrets |
| `k8s/vault/` | Vault policy + vault-auth RBAC |
| `k8s/external-secrets/` | ClusterSecretStore + ExternalSecrets |

## Still in GitHub Secrets (not Vault)

| Secret | Why |
|--------|-----|
| `VM_SSH_PRIVATE_KEY`, `VM_HOST` | CI SSH deploy |
| `GHCR_TOKEN` | Image pull during deploy |

Optional later: move `GHCR_TOKEN` to Vault + ESO docker-registry secret.
