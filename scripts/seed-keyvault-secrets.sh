#!/usr/bin/env bash
# Upload Odoo DB credentials to Azure Key Vault (ESO syncs to Kubernetes).
#
#   export DB_USER=... DB_PASSWORD=... STAGING_DB_PASSWORD=...
#   ./scripts/seed-keyvault-secrets.sh
#
# Requires: az login, terraform apply (Key Vault + RBAC), Vault Administrator on your user.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_env

KV_NAME="${KEY_VAULT_NAME:-}"
if [[ -z "$KV_NAME" ]] && [[ -d "${REPO_DIR}/terraform" ]]; then
  KV_NAME="$(terraform -chdir="${REPO_DIR}/terraform" output -raw key_vault_name 2>/dev/null || true)"
fi
: "${KV_NAME:?Set KEY_VAULT_NAME or run terraform apply}"

if [[ -z "${POSTGRES_FQDN:-}" ]] && [[ -d "${REPO_DIR}/terraform" ]]; then
  POSTGRES_FQDN="$(terraform -chdir="${REPO_DIR}/terraform" output -raw postgres_fqdn 2>/dev/null || true)"
  export POSTGRES_FQDN
fi

: "${POSTGRES_FQDN:?}"
: "${DB_USER:?}"
: "${DB_PASSWORD:?}"
: "${STAGING_DB_PASSWORD:?}"

PROD_DB="${POSTGRES_DB:-odoo_devops_lab}"
STAGING_DB="${STAGING_POSTGRES_DB:-odoo_staging}"
STAGING_USER="${STAGING_DB_USER:-odoo_staging}"
PGBOUNCER_SVC="${PGBOUNCER_HOST:-pgbouncer.odoo.svc.cluster.local}"
STAGING_PG_SVC="${STAGING_PG_HOST:-postgres-staging.odoo.svc.cluster.local}"

set_secret() {
  az keyvault secret set --vault-name "$KV_NAME" --name "$1" --value "$2" --only-show-errors -o none
}

echo "[keyvault] Writing secrets to ${KV_NAME}..."
set_secret odoo-prod-db-host "$PGBOUNCER_SVC"
set_secret odoo-prod-db-user "$DB_USER"
set_secret odoo-prod-db-password "$DB_PASSWORD"
set_secret odoo-prod-postgres-host "$POSTGRES_FQDN"
set_secret odoo-prod-postgres-db "$PROD_DB"

set_secret odoo-staging-db-host "$STAGING_PG_SVC"
set_secret odoo-staging-db-user "$STAGING_USER"
set_secret odoo-staging-db-password "$STAGING_DB_PASSWORD"
set_secret odoo-staging-postgres-db "$STAGING_DB"
set_secret odoo-staging-postgres-user "$STAGING_USER"
set_secret odoo-staging-postgres-password "$STAGING_DB_PASSWORD"

echo "[keyvault] Done. Next: ./scripts/install-external-secrets-azure.sh"
