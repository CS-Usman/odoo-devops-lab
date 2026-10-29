#!/usr/bin/env bash
# One-time: copy secrets from .env into Vault KV (secret/odoo/*).
# Run after: vault operator init/unseal + vault secrets enable -path=secret kv-v2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${REPO_DIR}/.env"

export VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
export VAULT_CACERT="${VAULT_CACERT:-/opt/vault/tls/tls.crt}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

: "${DB_USER:?Set DB_USER in .env}"
: "${DB_PASSWORD:?Set DB_PASSWORD in .env}"

# AKS: Odoo → PgBouncer; PgBouncer → Azure Postgres FQDN
POSTGRES_HOST="${POSTGRES_HOST:-${DB_HOST:?Set POSTGRES_HOST or DB_HOST (Azure FQDN) in .env}}"
DB_HOST="${DB_HOST:-pgbouncer.odoo.svc.cluster.local}"

STAGING_USER="${STAGING_DB_USER:-odoo_staging}"
STAGING_PASSWORD="${STAGING_DB_PASSWORD:-change-me-staging}"
STAGING_DB="${ODOO_STAGING_DB_NAME:-odoo_staging}"

if ! vault status >/dev/null 2>&1; then
  echo "[vault] Vault unreachable or sealed" >&2
  exit 1
fi

vault secrets enable -path=secret kv-v2 2>/dev/null || true

echo "[vault] Write secret/odoo/prod..."
vault kv put secret/odoo/prod \
  DB_HOST="$DB_HOST" \
  POSTGRES_HOST="$POSTGRES_HOST" \
  POSTGRES_DB="${ODOO_DB_NAME:-odoo_devops_lab}" \
  DB_USER="$DB_USER" \
  DB_PASSWORD="$DB_PASSWORD" \
  ODOO_DB_NAME="${ODOO_DB_NAME:-odoo_devops_lab}"

echo "[vault] Write secret/odoo/staging..."
vault kv put secret/odoo/staging \
  DB_HOST="${STAGING_DB_HOST:-postgres-staging.odoo.svc.cluster.local}" \
  DB_USER="$STAGING_USER" \
  DB_PASSWORD="$STAGING_PASSWORD" \
  POSTGRES_DB="$STAGING_DB"

if [[ -n "${AZURE_STORAGE_ACCOUNT:-}" && -n "${AZURE_STORAGE_KEY:-}" ]]; then
  echo "[vault] Write secret/odoo/backup..."
  vault kv put secret/odoo/backup \
    AZURE_STORAGE_ACCOUNT="$AZURE_STORAGE_ACCOUNT" \
    AZURE_STORAGE_CONTAINER="${AZURE_STORAGE_CONTAINER:-odoo-backups}" \
    AZURE_STORAGE_KEY="$AZURE_STORAGE_KEY"
fi

echo "[vault] Done. Verify: vault kv get secret/odoo/prod"
